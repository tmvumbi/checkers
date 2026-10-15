import { v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import {
  internalMutation,
  mutation,
  query,
  type MutationCtx,
  type QueryCtx,
} from "./_generated/server";
import { currentProfile, requirePlayer, requireProfile } from "./lib/auth";
import {
  clockConfig,
  leaderboardMinGames,
  pointRules as pointRulesOf,
  publicConfig,
} from "./lib/config";
import { checkersEngine } from "./lib/engine.js";
import { fail } from "./lib/errors";
import {
  assertPreset,
  currentPly,
  deleteGameCascade,
  engineConfig,
  finishGame,
  finishOnTime,
  getGame,
  insertWaitingGame,
  leaveWaitingGame,
  other,
  rearmTimeout,
  requireSeat,
  seatPlayer,
  seatsOf,
  sideToMove,
  startGame,
} from "./lib/games";
import { gamePlayerRow, gameRow, leaderboardRow } from "./lib/serialize";

// Online games: matchmaking, server-authoritative moves and clocks, draws,
// rematches, resume, archives and leaderboards. Port of the RPCs in
// supabase/migrations 0003, 0005, 0006, 0009, 0023, 0030, 0033.

const LOBBY_HEARTBEAT_MS = 60_000;

async function gameWithPlayers(ctx: QueryCtx, game: Doc<"games">) {
  const players = await seatsOf(ctx, game._id);
  return {
    ...gameRow(game),
    game_players: players.sort((a, b) => a.seat - b.seat).map(gamePlayerRow),
  };
}

async function requireGame(ctx: QueryCtx, gameId: string) {
  const game = await getGame(ctx, gameId);
  if (!game) fail("game_not_found");
  return game;
}

// ---------------------------------------------------------------------
// Matchmaking
// ---------------------------------------------------------------------

/** `join_online_game`: seat the caller in the oldest open public lobby of
 * this preset, or open a new one. The second seat starts the game. */
export const joinOnlineGame = mutation({
  args: { preset: v.string() },
  handler: async (ctx, { preset }) => {
    const me = await requirePlayer(ctx);
    assertPreset(preset);
    const now = Date.now();

    // Leave any current waiting games first (idempotent re-join).
    const myWaiting = await ctx.db
      .query("gamePlayers")
      .withIndex("by_uid_and_status", (q) => q.eq("uid", me._id).eq("gameStatus", "waiting"))
      .take(20);
    for (const seat of myWaiting) {
      await leaveWaitingGame(ctx, seat.gameId, me._id);
    }

    // GC abandoned lobbies: waiting over a minute with no live heartbeat.
    const waiting = await ctx.db
      .query("games")
      .withIndex("by_status_and_private_and_preset", (q) => q.eq("status", "waiting"))
      .take(200);
    for (const game of waiting) {
      if (game.createdAt >= now - LOBBY_HEARTBEAT_MS) continue;
      const seats = await seatsOf(ctx, game._id);
      if (!seats.some((s) => s.lastSeenAt > now - LOBBY_HEARTBEAT_MS)) {
        await deleteGameCascade(ctx, game._id);
      }
    }

    // Oldest open public lobby for this preset (creation order).
    let open: Doc<"games"> | null = null;
    for await (const game of ctx.db
      .query("games")
      .withIndex("by_status_and_private_and_preset", (q) =>
        q.eq("status", "waiting").eq("isPrivate", false).eq("preset", preset),
      )) {
      if (!(await ctx.db.get("games", game._id))) continue; // GC'd above
      const seats = await seatsOf(ctx, game._id);
      if (seats.length >= 2 || seats.some((s) => s.uid === me._id)) continue;
      open = game;
      break;
    }

    let gameId: Id<"games">;
    let seat: number;
    if (!open) {
      gameId = await insertWaitingGame(ctx, { preset, hostUid: me._id });
      seat = 0;
    } else {
      gameId = open._id;
      const seats = await seatsOf(ctx, gameId);
      seat = seats.length ? Math.max(...seats.map((s) => s.seat)) + 1 : 0;
    }
    const game = (await ctx.db.get("games", gameId))!;
    await seatPlayer(ctx, game, {
      seat,
      uid: me._id,
      nickname: me.nickname,
      photoUrl: me.photoUrl,
    });
    if (seat === 1) await startGame(ctx, gameId);
    return { game_id: gameId, seat };
  },
});

// ---------------------------------------------------------------------
// Live play
// ---------------------------------------------------------------------

/** `submit_move`: validates turn, ply and clock, applies the move through
 * the shared engine, records it and passes the clock. */
export const submitMove = mutation({
  args: { gameId: v.string(), move: v.any(), expectedPly: v.number() },
  handler: async (ctx, { gameId, move, expectedPly }) => {
    const me = await requireProfile(ctx);
    const game = await requireGame(ctx, gameId);
    if (game.status !== "playing") fail("game_not_playing");
    const seat = await requireSeat(ctx, game._id, me._id);
    const mover = sideToMove(game);
    if (seat.color !== mover) fail("not_your_turn");
    if (currentPly(game) !== expectedPly) fail("stale_move");

    // Clock: the configured allowance per move; excess drains the bank.
    const { turnMs } = await clockConfig(ctx);
    const now = Date.now();
    const elapsed = Math.floor(now - (game.turnStartedAt ?? now));
    let bank = mover === "white" ? game.whiteBankMs : game.blackBankMs;
    if (elapsed > turnMs) bank -= elapsed - turnMs;
    if (bank < 0) {
      await finishOnTime(ctx, game);
      return { status: "timeout" };
    }

    const applied = checkersEngine("apply_move", {
      config: engineConfig(game),
      state: game.state,
      move,
    });
    if (applied.error) fail("illegal_move");
    const state = applied.state;

    await ctx.db.insert("gameMoves", {
      gameId: game._id,
      ply: expectedPly,
      color: mover,
      move: applied.move,
      msSpent: elapsed,
      playedAt: now,
    });
    const otherBank = mover === "white" ? game.blackBankMs : game.whiteBankMs;
    await ctx.db.patch("games", game._id, {
      state,
      lastMove: applied.move,
      whiteBankMs: mover === "white" ? bank : game.whiteBankMs,
      blackBankMs: mover === "black" ? bank : game.blackBankMs,
      drawOfferColor: game.drawOfferColor === mover ? mover : undefined,
      turnStartedAt: now,
      turnDeadlineAt: now + turnMs + otherBank,
      updatedAt: now,
    });

    if (state.result !== "ongoing") {
      await finishGame(
        ctx,
        game._id,
        state.result,
        state.result_reason,
        state.result === "whiteWin" ? "white" : state.result === "blackWin" ? "black" : null,
      );
    } else {
      await rearmTimeout(ctx, game._id);
    }
    return { status: "ok", ply: expectedPly + 1 };
  },
});

/** Scheduled at each turn deadline: flag fall unless the position moved on. */
export const timeoutIfStale = internalMutation({
  args: { gameId: v.id("games"), ply: v.number() },
  handler: async (ctx, { gameId, ply }) => {
    const game = await ctx.db.get("games", gameId);
    if (!game || game.status !== "playing" || game.vsPc) return;
    if (currentPly(game) !== ply || game.turnDeadlineAt === undefined) return;
    if (Date.now() < game.turnDeadlineAt) {
      await rearmTimeout(ctx, gameId);
      return;
    }
    await finishOnTime(ctx, game);
  },
});

/** `claim_timeout`: either player may claim an expired clock. */
export const claimTimeout = mutation({
  args: { gameId: v.string() },
  handler: async (ctx, { gameId }) => {
    const game = await getGame(ctx, gameId);
    if (!game || game.status !== "playing") return { status: "noop" };
    if (game.turnDeadlineAt === undefined || Date.now() < game.turnDeadlineAt) {
      return { status: "not_expired" };
    }
    await finishOnTime(ctx, game);
    return { status: "timeout_applied" };
  },
});

async function resign(ctx: MutationCtx, game: Doc<"games">, uid: Id<"profiles">) {
  const seat = await requireSeat(ctx, game._id, uid);
  const color = seat.color ?? "white";
  await finishGame(
    ctx,
    game._id,
    color === "white" ? "blackWin" : "whiteWin",
    "resignation",
    other(color),
  );
  return { status: "resigned" };
}

export const resignGame = mutation({
  args: { gameId: v.string() },
  handler: async (ctx, { gameId }) => {
    const me = await requireProfile(ctx);
    const game = await getGame(ctx, gameId);
    if (!game || game.status !== "playing") return { status: "noop" };
    return await resign(ctx, game, me._id);
  },
});

/** `leave_game`: leave a lobby, or resign a live game. */
export const leaveGame = mutation({
  args: { gameId: v.string() },
  handler: async (ctx, { gameId }) => {
    const me = await requireProfile(ctx);
    const game = await getGame(ctx, gameId);
    if (!game) return { status: "noop" };
    if (game.status === "waiting") {
      await leaveWaitingGame(ctx, game._id, me._id);
      return { status: "left" };
    }
    if (game.status === "playing") return await resign(ctx, game, me._id);
    return { status: "noop" };
  },
});

/** `touch_game_connection`: lobby / in-game heartbeat (~20 s). */
export const touchConnection = mutation({
  args: { gameId: v.string(), connected: v.boolean() },
  handler: async (ctx, { gameId, connected }) => {
    const me = await currentProfile(ctx);
    const id = ctx.db.normalizeId("games", gameId);
    if (!me || !id) return null;
    const seat = await ctx.db
      .query("gamePlayers")
      .withIndex("by_game_and_uid", (q) => q.eq("gameId", id).eq("uid", me._id))
      .unique();
    if (seat) {
      await ctx.db.patch("gamePlayers", seat._id, { connected, lastSeenAt: Date.now() });
    }
    return null;
  },
});

export const offerDraw = mutation({
  args: { gameId: v.string() },
  handler: async (ctx, { gameId }) => {
    const me = await requireProfile(ctx);
    const game = await getGame(ctx, gameId);
    if (!game || game.status !== "playing") return { status: "noop" };
    const seat = await requireSeat(ctx, game._id, me._id);
    if (game.drawOfferColor) return { status: "already_offered" };
    await ctx.db.patch("games", game._id, { drawOfferColor: seat.color, updatedAt: Date.now() });
    return { status: "offered" };
  },
});

export const respondDraw = mutation({
  args: { gameId: v.string(), accept: v.boolean() },
  handler: async (ctx, { gameId, accept }) => {
    const me = await requireProfile(ctx);
    const game = await getGame(ctx, gameId);
    if (!game || game.status !== "playing" || !game.drawOfferColor) return { status: "noop" };
    const seat = await requireSeat(ctx, game._id, me._id);
    if (seat.color === game.drawOfferColor) fail("cannot_respond_to_own_offer");
    if (accept) {
      await finishGame(ctx, game._id, "draw", "agreement", null);
      return { status: "draw_agreed" };
    }
    await ctx.db.patch("games", game._id, { drawOfferColor: undefined, updatedAt: Date.now() });
    return { status: "declined" };
  },
});

/** `request_rematch`: the second requester starts the rematch, colors swapped. */
export const requestRematch = mutation({
  args: { gameId: v.string() },
  handler: async (ctx, { gameId }) => {
    const me = await requireProfile(ctx);
    const game = await getGame(ctx, gameId);
    if (!game || game.status !== "finished") return { status: "noop" };
    await requireSeat(ctx, game._id, me._id);
    if (game.rematchGameId) return { status: "ready", game_id: game.rematchGameId };
    if (!game.rematchRequestedBy) {
      await ctx.db.patch("games", game._id, { rematchRequestedBy: me._id, updatedAt: Date.now() });
      return { status: "requested" };
    }
    if (game.rematchRequestedBy === me._id) return { status: "requested" };

    const newId = await insertWaitingGame(ctx, {
      preset: game.preset,
      rules: {
        boardSize: game.boardSize,
        backwardCapture: game.backwardCapture,
        flyingKing: game.flyingKing,
        majorityCapture: game.majorityCapture,
      },
      hostUid: me._id,
      isPrivate: game.isPrivate,
      rated: game.rated,
    });
    const fresh = (await ctx.db.get("games", newId))!;
    for (const p of await seatsOf(ctx, game._id)) {
      await seatPlayer(ctx, fresh, {
        seat: p.seat,
        uid: p.uid,
        nickname: p.nickname,
        photoUrl: p.photoUrl,
        color: p.color ? other(p.color) : undefined,
        isBot: p.isBot,
      });
    }
    await startGame(ctx, newId);
    await ctx.db.patch("games", game._id, { rematchGameId: newId, updatedAt: Date.now() });
    return { status: "ready", game_id: newId };
  },
});

/** Clock-skew probe (`server_time`). A mutation so it is never cached. */
export const serverTime = mutation({
  args: {},
  handler: async () => new Date().toISOString(),
});

// ---------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------

/** One game row with its seats (`games` + `game_players`), reactive. */
export const get = query({
  args: { gameId: v.string() },
  handler: async (ctx, { gameId }) => {
    const game = await getGame(ctx, gameId);
    return game ? await gameWithPlayers(ctx, game) : null;
  },
});

/** Recorded moves in ply order (`game_moves`). */
export const moves = query({
  args: { gameId: v.string() },
  handler: async (ctx, { gameId }) => {
    const id = ctx.db.normalizeId("games", gameId);
    if (!id) return [];
    const rows = await ctx.db
      .query("gameMoves")
      .withIndex("by_game_and_ply", (q) => q.eq("gameId", id))
      .take(2000);
    return rows.map((m) => ({ ply: m.ply, move: m.move }));
  },
});

function clampPage(offset: number | undefined, limit: number | undefined, max: number, fallback: number) {
  return {
    offset: Math.max(Math.trunc(offset ?? 0), 0),
    limit: Math.min(Math.max(Math.trunc(limit ?? fallback), 1), max),
  };
}

/** Every live game, newest first (Watch tab). */
export const watchable = query({
  args: { offset: v.optional(v.number()), limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const { offset, limit } = clampPage(args.offset, args.limit, 50, 30);
    const games = await ctx.db
      .query("games")
      .withIndex("by_status_and_started", (q) => q.eq("status", "playing"))
      .order("desc")
      .take(offset + limit);
    return await Promise.all(games.slice(offset).map((g) => gameWithPlayers(ctx, g)));
  },
});

/** `list_recent_games`: finished public games, newest first. */
export const recent = query({
  args: {
    search: v.optional(v.union(v.string(), v.null())),
    mine: v.optional(v.boolean()),
    offset: v.optional(v.number()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const { offset, limit } = clampPage(args.offset, args.limit, 30, 10);
    const needle = (args.search ?? "").trim().toLowerCase();
    const wanted = offset + limit;
    let games: Doc<"games">[] = [];

    if (args.mine) {
      const me = await currentProfile(ctx);
      if (!me) return [];
      const seats = await ctx.db
        .query("gamePlayers")
        .withIndex("by_uid_and_status", (q) => q.eq("uid", me._id).eq("gameStatus", "finished"))
        .order("desc")
        .take(1000);
      for (const seat of seats) {
        const game = await ctx.db.get("games", seat.gameId);
        if (!game || game.isPrivate) continue;
        if (needle && !(game.playerSearch ?? "").includes(needle)) continue;
        games.push(game);
      }
      games.sort((a, b) => (b.finishedAt ?? 0) - (a.finishedAt ?? 0));
      games = games.slice(offset, wanted);
    } else {
      let scanned = 0;
      for await (const game of ctx.db
        .query("games")
        .withIndex("by_status_and_private_and_finished", (q) =>
          q.eq("status", "finished").eq("isPrivate", false),
        )
        .order("desc")) {
        if (++scanned > 3000 || games.length >= wanted) break;
        if (needle && !(game.playerSearch ?? "").includes(needle)) continue;
        games.push(game);
      }
      games = games.slice(offset);
    }
    return await Promise.all(games.map((g) => gameWithPlayers(ctx, g)));
  },
});

/** `my_active_game`: the in-progress human game the caller is seated at. */
export const myActiveGame = query({
  args: {},
  handler: async (ctx) => {
    const me = await currentProfile(ctx);
    if (!me) return null;
    const seats = await ctx.db
      .query("gamePlayers")
      .withIndex("by_uid_and_status", (q) => q.eq("uid", me._id).eq("gameStatus", "playing"))
      .take(20);
    let best: { game: Doc<"games">; seat: Doc<"gamePlayers"> } | null = null;
    for (const seat of seats) {
      if (!seat.color) continue;
      const game = await ctx.db.get("games", seat.gameId);
      if (!game || game.vsPc || game.status !== "playing") continue;
      if (!best || (game.startedAt ?? 0) > (best.game.startedAt ?? 0)) best = { game, seat };
    }
    if (!best) return null;
    const { game, seat } = best;
    const opponent = (await seatsOf(ctx, game._id)).find((s) => s.uid !== me._id);
    return {
      game_id: game._id,
      color: seat.color,
      preset: game.preset,
      board_size: game.boardSize,
      backward_capture: game.backwardCapture,
      flying_king: game.flyingKing,
      majority_capture: game.majorityCapture,
      is_private: game.isPrivate,
      tournament_id: game.tournamentId ?? null,
      started_at: game.startedAt ? new Date(game.startedAt).toISOString() : null,
      turn_deadline_at: game.turnDeadlineAt ? new Date(game.turnDeadlineAt).toISOString() : null,
      my_turn: sideToMove(game) === seat.color,
      opponent_nickname: opponent?.nickname ?? "",
    };
  },
});

/** `get_leaderboard`: Top 30 by ELO among qualified players. */
export const leaderboard = query({
  args: {},
  handler: async (ctx) => {
    const minGames = leaderboardMinGames(await publicConfig(ctx));
    const rows: Doc<"profiles">[] = [];
    let scanned = 0;
    for await (const p of ctx.db.query("profiles").withIndex("by_rating").order("desc")) {
      if (++scanned > 5000 || rows.length >= 30) break;
      if (p.ratedGames >= minGames && p.nickname !== "") rows.push(p);
    }
    return rows.map(leaderboardRow);
  },
});

/** `get_points_leaderboard`: Top 30 by points (ties: rating, seniority). */
export const pointsLeaderboard = query({
  args: {},
  handler: async (ctx) => {
    const rows: Doc<"profiles">[] = [];
    let scanned = 0;
    for await (const p of ctx.db
      .query("profiles")
      .withIndex("by_points_and_rating", (q) => q.gt("points", 0))
      .order("desc")) {
      if (++scanned > 5000) break;
      if (p.nickname !== "") rows.push(p);
      if (rows.length >= 60) break;
    }
    rows.sort(
      (a, b) => b.points - a.points || b.rating - a.rating || a.createdAt - b.createdAt,
    );
    return rows.slice(0, 30).map(leaderboardRow);
  },
});

/** `get_point_rules`. */
export const pointRules = query({
  args: {},
  handler: async (ctx) => pointRulesOf(await publicConfig(ctx)),
});
