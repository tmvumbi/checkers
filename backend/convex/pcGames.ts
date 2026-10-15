import { v } from "convex/values";
import { mutation } from "./_generated/server";
import { requirePlayer, requireProfile } from "./lib/auth";
import { checkersEngine } from "./lib/engine.js";
import { fail } from "./lib/errors";
import {
  abandonGame,
  currentPly,
  engineConfig,
  finishGame,
  getGame,
  requireSeat,
  seatPlayer,
  sideToMove,
} from "./lib/games";

// Streamed PC games (0010): the client plays the AI locally and streams its
// game here so it shows in Watch; every move is re-validated by the engine.
// Unrated, no clocks.

/** `start_pc_game`. A player streams at most one PC game at a time. */
export const start = mutation({
  args: {
    boardSize: v.number(),
    backwardCapture: v.boolean(),
    flyingKing: v.boolean(),
    majorityCapture: v.boolean(),
    aiLevel: v.string(),
    allowUndo: v.boolean(),
    humanColor: v.string(),
  },
  handler: async (ctx, args) => {
    const me = await requirePlayer(ctx);
    if (
      (args.humanColor !== "white" && args.humanColor !== "black") ||
      !["easy", "medium", "hard"].includes(args.aiLevel) ||
      (args.boardSize !== 8 && args.boardSize !== 10)
    ) {
      fail("invalid_arguments");
    }
    const humanColor = args.humanColor as "white" | "black";

    const live = await ctx.db
      .query("gamePlayers")
      .withIndex("by_uid_and_status", (q) => q.eq("uid", me._id).eq("gameStatus", "playing"))
      .take(20);
    for (const seat of live) {
      const game = await ctx.db.get("games", seat.gameId);
      if (game?.vsPc && game.status === "playing") await abandonGame(ctx, game._id);
    }

    const { boardSize, backwardCapture, flyingKing, majorityCapture } = args;
    const all = backwardCapture && flyingKing && majorityCapture;
    const none = !backwardCapture && !flyingKing && !majorityCapture;
    const preset =
      boardSize === 10 && all
        ? "international"
        : boardSize === 8 && all
          ? "brazilian"
          : boardSize === 8 && none
            ? "american"
            : "custom";
    const rules = { boardSize, backwardCapture, flyingKing, majorityCapture };
    const now = Date.now();
    const gameId = await ctx.db.insert("games", {
      status: "playing",
      preset,
      ...rules,
      isPrivate: false,
      allowSocialJoin: false,
      rated: false,
      hostUid: me._id,
      state: checkersEngine("initial_state", { config: engineConfig(rules) }),
      whiteBankMs: 300000,
      blackBankMs: 300000,
      vsPc: true,
      aiLevel: args.aiLevel,
      allowUndo: args.allowUndo,
      createdAt: now,
      startedAt: now,
      updatedAt: now,
    });
    const game = (await ctx.db.get("games", gameId))!;
    await seatPlayer(ctx, game, {
      seat: 0,
      uid: me._id,
      nickname: me.nickname,
      photoUrl: me.photoUrl,
      color: humanColor,
    });
    await seatPlayer(ctx, game, {
      seat: 1,
      nickname: "PC",
      color: humanColor === "white" ? "black" : "white",
      isBot: true,
    });
    return { game_id: gameId };
  },
});

async function requirePcGame(
  ctx: Parameters<typeof getGame>[0],
  gameId: string,
) {
  const game = await getGame(ctx, gameId);
  if (!game || !game.vsPc) fail("game_not_found");
  return game;
}

/** `submit_pc_move`: either side's move (the client plays both). */
export const submitMove = mutation({
  args: { gameId: v.string(), move: v.any(), expectedPly: v.number() },
  handler: async (ctx, { gameId, move, expectedPly }) => {
    const me = await requireProfile(ctx);
    const game = await requirePcGame(ctx, gameId);
    if (game.status !== "playing") fail("game_not_playing");
    await requireSeat(ctx, game._id, me._id);
    if (currentPly(game) !== expectedPly) fail("stale_move");

    const mover = sideToMove(game);
    const applied = checkersEngine("apply_move", {
      config: engineConfig(game),
      state: game.state,
      move,
    });
    if (applied.error) fail("illegal_move");
    const state = applied.state;
    const now = Date.now();
    await ctx.db.insert("gameMoves", {
      gameId: game._id,
      ply: expectedPly,
      color: mover,
      move: applied.move,
      msSpent: 0,
      playedAt: now,
    });
    await ctx.db.patch("games", game._id, { state, lastMove: applied.move, updatedAt: now });
    if (state.result !== "ongoing") {
      await finishGame(
        ctx,
        game._id,
        state.result,
        state.result_reason,
        state.result === "whiteWin" ? "white" : state.result === "blackWin" ? "black" : null,
      );
    }
    return { status: "ok", ply: expectedPly + 1 };
  },
});

/** `undo_pc_moves`: drops the last 1-4 plies and replays the rest. */
export const undoMoves = mutation({
  args: { gameId: v.string(), count: v.number() },
  handler: async (ctx, { gameId, count }) => {
    if (count < 1 || count > 4) fail("invalid_arguments");
    const me = await requireProfile(ctx);
    const game = await requirePcGame(ctx, gameId);
    if (game.status !== "playing" || !game.allowUndo) fail("undo_not_allowed");
    await requireSeat(ctx, game._id, me._id);

    const keep = Math.max(0, currentPly(game) - count);
    const all = await ctx.db
      .query("gameMoves")
      .withIndex("by_game_and_ply", (q) => q.eq("gameId", game._id))
      .take(2000);
    for (const m of all) {
      if (m.ply >= keep) await ctx.db.delete("gameMoves", m._id);
    }
    const kept = all.filter((m) => m.ply < keep);
    const replayed = checkersEngine("replay", {
      config: engineConfig(game),
      moves: kept.map((m) => m.move),
    });
    if (replayed.error) fail("replay_failed");
    await ctx.db.patch("games", game._id, {
      state: replayed.state,
      lastMove: keep > 0 ? kept[kept.length - 1]?.move : undefined,
      updatedAt: Date.now(),
    });
    return { status: "ok", ply: keep };
  },
});
