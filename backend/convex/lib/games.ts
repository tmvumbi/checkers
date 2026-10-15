import { internal } from "../_generated/api";
import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import { assertNotBlockedForPlay } from "./blocks";
import { clockConfig, pointRuleInt, publicConfig } from "./config";
import { checkersEngine } from "./engine.js";
import { fail } from "./errors";
import { recordPointAward } from "./points";
import { onTournamentGameFinished } from "./tournaments";

// Shared game machinery: the Convex port of the plpgsql helpers in
// 0003/0005/0010/0030 (_game_config, _finish_game, _apply_elo, the
// "start with random colors" blocks) plus the per-game timeout timer that
// replaces the 30-second pg_cron flag-fall sweep.

export type Color = "white" | "black";
export type GameStatus = Doc<"games">["status"];

export const PRESETS = ["international", "brazilian", "american"] as const;

export function other(color: Color): Color {
  return color === "white" ? "black" : "white";
}

export function assertPreset(preset: string) {
  if (!(PRESETS as readonly string[]).includes(preset)) fail("invalid_preset");
}

export function presetRules(preset: string) {
  const international = preset !== "american";
  return {
    boardSize: preset === "international" ? 10 : 8,
    backwardCapture: international,
    flyingKing: international,
    majorityCapture: international,
  };
}

/** `_game_config(g)`: the engine's rules payload. */
export function engineConfig(g: {
  boardSize: number;
  backwardCapture: boolean;
  flyingKing: boolean;
  majorityCapture: boolean;
}) {
  return {
    board_size: g.boardSize,
    backward_capture: g.backwardCapture,
    flying_king: g.flyingKing,
    majority_capture: g.majorityCapture,
  };
}

export function sideToMove(game: Doc<"games">): Color {
  return (game.state?.side ?? "white") as Color;
}

export function currentPly(game: Doc<"games">): number {
  return Number(game.state?.ply ?? 0);
}

export async function seatsOf(ctx: QueryCtx, gameId: Id<"games">) {
  return await ctx.db
    .query("gamePlayers")
    .withIndex("by_game_and_seat", (q) => q.eq("gameId", gameId))
    .take(2);
}

export async function seatOf(ctx: QueryCtx, gameId: Id<"games">, uid: Id<"profiles">) {
  return await ctx.db
    .query("gamePlayers")
    .withIndex("by_game_and_uid", (q) => q.eq("gameId", gameId).eq("uid", uid))
    .unique();
}

/** Requires the caller to be seated at [gameId]. */
export async function requireSeat(ctx: QueryCtx, gameId: Id<"games">, uid: Id<"profiles">) {
  const seat = await seatOf(ctx, gameId, uid);
  if (!seat) fail("not_a_player");
  return seat;
}

export async function getGame(ctx: QueryCtx, gameId: string): Promise<Doc<"games"> | null> {
  const id = ctx.db.normalizeId("games", gameId);
  return id ? await ctx.db.get("games", id) : null;
}

type NewGame = {
  preset: string;
  rules?: ReturnType<typeof presetRules>;
  hostUid?: Id<"profiles">;
  isPrivate?: boolean;
  allowSocialJoin?: boolean;
  rated?: boolean;
  vsPc?: boolean;
  aiLevel?: string;
  allowUndo?: boolean;
  tournamentId?: Id<"tournaments">;
};

/** Inserts a `waiting` game (clocks get their real values at start). */
export async function insertWaitingGame(ctx: MutationCtx, args: NewGame) {
  const now = Date.now();
  const rules = args.rules ?? presetRules(args.preset);
  return await ctx.db.insert("games", {
    status: "waiting",
    preset: args.preset,
    ...rules,
    isPrivate: args.isPrivate ?? false,
    allowSocialJoin: args.allowSocialJoin ?? false,
    rated: args.rated ?? true,
    hostUid: args.hostUid,
    whiteBankMs: 300000,
    blackBankMs: 300000,
    vsPc: args.vsPc ?? false,
    aiLevel: args.aiLevel,
    allowUndo: args.allowUndo ?? false,
    tournamentId: args.tournamentId,
    createdAt: now,
    updatedAt: now,
  });
}

/**
 * Seats a player (the old game_players insert). Human seats are checked
 * against blocks, as the `enforce_play_block` trigger did.
 */
export async function seatPlayer(
  ctx: MutationCtx,
  game: { _id: Id<"games">; status: GameStatus },
  seat: {
    seat: number;
    uid?: Id<"profiles">;
    nickname: string;
    photoUrl?: string;
    color?: Color;
    isBot?: boolean;
  },
  options: { checkBlock?: boolean } = {},
) {
  if (seat.uid && options.checkBlock !== false) {
    await assertNotBlockedForPlay(ctx, seat.uid);
  }
  return await ctx.db.insert("gamePlayers", {
    gameId: game._id,
    seat: seat.seat,
    uid: seat.uid,
    nickname: seat.nickname,
    photoUrl: seat.photoUrl,
    color: seat.color,
    connected: true,
    lastSeenAt: Date.now(),
    isBot: seat.isBot ?? false,
    gameStatus: game.status,
  });
}

/** Keeps gamePlayers.gameStatus in step with the game. */
async function mirrorStatus(ctx: MutationCtx, gameId: Id<"games">, status: GameStatus) {
  for (const p of await seatsOf(ctx, gameId)) {
    if (p.gameStatus !== status) {
      await ctx.db.patch("gamePlayers", p._id, { gameStatus: status });
    }
  }
}

/** (Re)arms the flag-fall timer for the side to move. */
async function armTimeout(
  ctx: MutationCtx,
  game: Doc<"games">,
  deadline: number,
  ply: number,
): Promise<Id<"_scheduled_functions">> {
  await cancelTimeout(ctx, game);
  return await ctx.scheduler.runAt(deadline, internal.games.timeoutIfStale, {
    gameId: game._id,
    ply,
  });
}

async function cancelTimeout(ctx: MutationCtx, game: Doc<"games">) {
  if (!game.timeoutJobId) return;
  const job = await ctx.db.system.get("_scheduled_functions", game.timeoutJobId);
  if (job && job.state.kind === "pending") {
    await ctx.scheduler.cancel(game.timeoutJobId);
  }
}

/**
 * Starts a game whose two seats are filled: random colors unless both seats
 * already have one, initial engine state, clocks from config, timer armed.
 */
export async function startGame(ctx: MutationCtx, gameId: Id<"games">) {
  const game = (await ctx.db.get("games", gameId))!;
  const seats = await seatsOf(ctx, gameId);
  if (seats.some((s) => !s.color)) {
    const first: Color = Math.random() < 0.5 ? "white" : "black";
    for (const s of seats) {
      await ctx.db.patch("gamePlayers", s._id, { color: s.seat === 0 ? first : other(first) });
    }
  }
  const { turnMs, bankMs } = await clockConfig(ctx);
  const now = Date.now();
  const state = checkersEngine("initial_state", { config: engineConfig(game) });
  const deadline = now + turnMs + bankMs;
  await ctx.db.patch("games", gameId, {
    status: "playing",
    state,
    startedAt: now,
    turnStartedAt: now,
    turnDeadlineAt: deadline,
    whiteBankMs: bankMs,
    blackBankMs: bankMs,
    updatedAt: now,
  });
  await mirrorStatus(ctx, gameId, "playing");
  const started = (await ctx.db.get("games", gameId))!;
  const jobId = await armTimeout(ctx, started, deadline, Number(state.ply ?? 0));
  await ctx.db.patch("games", gameId, { timeoutJobId: jobId });
}

/** After a human move: re-arm the timer for the opponent. */
export async function rearmTimeout(ctx: MutationCtx, gameId: Id<"games">) {
  const game = (await ctx.db.get("games", gameId))!;
  if (game.status !== "playing" || game.vsPc || game.turnDeadlineAt === undefined) return;
  const jobId = await armTimeout(ctx, game, game.turnDeadlineAt, currentPly(game));
  await ctx.db.patch("games", gameId, { timeoutJobId: jobId });
}

function scoreOf(result: string): number {
  return result === "whiteWin" ? 1 : result === "blackWin" ? 0 : 0.5;
}

/** `_apply_elo`: K=32 under 30 rated games else 16, floor 100. */
async function applyElo(ctx: MutationCtx, gameId: Id<"games">, score: number) {
  const seats = await seatsOf(ctx, gameId);
  const whiteSeat = seats.find((s) => s.color === "white");
  const blackSeat = seats.find((s) => s.color === "black");
  if (!whiteSeat?.uid || !blackSeat?.uid) return;
  const white = await ctx.db.get("profiles", whiteSeat.uid);
  const black = await ctx.db.get("profiles", blackSeat.uid);
  if (!white || !black) return;

  const kWhite = white.ratedGames < 30 ? 32 : 16;
  const kBlack = black.ratedGames < 30 ? 32 : 16;
  const expWhite = 1 / (1 + Math.pow(10, (black.rating - white.rating) / 400));
  const newWhite = Math.max(100, Math.round(white.rating + kWhite * (score - expWhite)));
  const newBlack = Math.max(
    100,
    Math.round(black.rating + kBlack * (1 - score - (1 - expWhite))),
  );

  await ctx.db.patch("gamePlayers", whiteSeat._id, {
    ratingBefore: white.rating,
    ratingAfter: newWhite,
  });
  await ctx.db.patch("gamePlayers", blackSeat._id, {
    ratingBefore: black.rating,
    ratingAfter: newBlack,
  });
  const now = Date.now();
  await ctx.db.patch("profiles", white._id, {
    rating: newWhite,
    ratedGames: white.ratedGames + 1,
    wins: white.wins + (score === 1 ? 1 : 0),
    losses: white.losses + (score === 0 ? 1 : 0),
    draws: white.draws + (score === 0.5 ? 1 : 0),
    updatedAt: now,
  });
  await ctx.db.patch("profiles", black._id, {
    rating: newBlack,
    ratedGames: black.ratedGames + 1,
    wins: black.wins + (score === 0 ? 1 : 0),
    losses: black.losses + (score === 1 ? 1 : 0),
    draws: black.draws + (score === 0.5 ? 1 : 0),
    updatedAt: now,
  });
}

/**
 * `_finish_game` plus the triggers that hung off `games` status changes:
 * ELO for rated games, PC-win points, tournament match close/advance.
 */
export async function finishGame(
  ctx: MutationCtx,
  gameId: Id<"games">,
  result: string,
  reason: string,
  winnerColor: Color | null,
) {
  const game = (await ctx.db.get("games", gameId))!;
  if (game.status === "finished") return;
  const seats = await seatsOf(ctx, gameId);
  const winner = winnerColor ? seats.find((s) => s.color === winnerColor) : undefined;
  const now = Date.now();
  await cancelTimeout(ctx, game);
  await ctx.db.patch("games", gameId, {
    status: "finished",
    result,
    resultReason: reason,
    winnerUid: winner?.uid,
    finishedAt: now,
    turnDeadlineAt: undefined,
    timeoutJobId: undefined,
    playerSearch: seats.map((s) => s.nickname.toLowerCase()).join("\n"),
    updatedAt: now,
  });
  await mirrorStatus(ctx, gameId, "finished");

  if (game.rated) {
    await applyElo(ctx, gameId, scoreOf(result));
  }
  if (game.vsPc && winner?.uid) {
    const config = await publicConfig(ctx);
    const points =
      game.aiLevel === "easy"
        ? pointRuleInt(config, "pc_easy_win", 1)
        : game.aiLevel === "medium"
          ? pointRuleInt(config, "pc_medium_win", 5)
          : game.aiLevel === "hard"
            ? pointRuleInt(config, "pc_hard_win", 10)
            : 0;
    await recordPointAward(ctx, {
      uid: winner.uid,
      awardType: "pc_win",
      sourceId: gameId,
      points,
      metadata: { ai_level: game.aiLevel ?? null },
    });
  }
  if (game.tournamentId) {
    const finished = (await ctx.db.get("games", gameId))!;
    await onTournamentGameFinished(ctx, finished);
  }
}

/** Timeout loss for the side to move. */
export async function finishOnTime(ctx: MutationCtx, game: Doc<"games">) {
  const mover = sideToMove(game);
  await finishGame(
    ctx,
    game._id,
    mover === "white" ? "blackWin" : "whiteWin",
    "timeout",
    other(mover),
  );
}

/** Streamed PC game dropped (new PC game started, or idle for 5 min). */
export async function abandonGame(ctx: MutationCtx, gameId: Id<"games">) {
  const now = Date.now();
  await ctx.db.patch("games", gameId, {
    status: "abandoned",
    result: undefined,
    resultReason: "abandonment",
    finishedAt: now,
    updatedAt: now,
  });
  await mirrorStatus(ctx, gameId, "abandoned");
}

/** Deletes a game and everything hanging off it (FK cascades). */
export async function deleteGameCascade(ctx: MutationCtx, gameId: Id<"games">) {
  const game = await ctx.db.get("games", gameId);
  if (game) await cancelTimeout(ctx, game);
  for (const p of await seatsOf(ctx, gameId)) await ctx.db.delete("gamePlayers", p._id);
  for await (const m of ctx.db
    .query("gameMoves")
    .withIndex("by_game_and_ply", (q) => q.eq("gameId", gameId))) {
    await ctx.db.delete("gameMoves", m._id);
  }
  for await (const i of ctx.db.query("invites").withIndex("by_game", (q) => q.eq("gameId", gameId))) {
    await ctx.db.delete("invites", i._id);
  }
  for await (const w of ctx.db
    .query("gameWatchers")
    .withIndex("by_game_and_uid", (q) => q.eq("gameId", gameId))) {
    await ctx.db.delete("gameWatchers", w._id);
  }
  for await (const e of ctx.db.query("gameEmotes").withIndex("by_game", (q) => q.eq("gameId", gameId))) {
    await ctx.db.delete("gameEmotes", e._id);
  }
  if (game) await ctx.db.delete("games", gameId);
}

/** Removes a player's seat from a waiting game; drops the game if empty. */
export async function leaveWaitingGame(
  ctx: MutationCtx,
  gameId: Id<"games">,
  uid: Id<"profiles">,
) {
  const seat = await seatOf(ctx, gameId, uid);
  if (seat) await ctx.db.delete("gamePlayers", seat._id);
  if ((await seatsOf(ctx, gameId)).length === 0) {
    await deleteGameCascade(ctx, gameId);
  }
}
