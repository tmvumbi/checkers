import { afterEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import { finishGame } from "./lib/games";
import { BLACK_OPENING, WHITE_OPENING, newBackend, player, type Backend } from "./test.setup";

// Port of scripts/test_online_flow.sh, test_social_flow.sh,
// test_pc_stream_flow.sh, test_resume_watch_flow.sh, test_block_flow.sh.

afterEach(() => {
  vi.useRealTimers();
});

async function setConfig(t: Backend, config: Record<string, unknown>) {
  await t.run(async (ctx) => {
    await ctx.db.insert("appConfig", { key: "public", config });
  });
}

type Player = Awaited<ReturnType<typeof player>>;

/** Matches two players into a started public game; returns them by color. */
async function startedGame(t: Backend) {
  const a = await player(t, "alice");
  const b = await player(t, "bob");
  const ja = await a.as.mutation(api.games.joinOnlineGame, { preset: "international" });
  const jb = await b.as.mutation(api.games.joinOnlineGame, { preset: "international" });
  expect(jb.game_id).toBe(ja.game_id);
  const game = (await a.as.query(api.games.get, { gameId: ja.game_id }))!;
  const whiteUid = game.game_players.find((p) => p.color === "white")!.uid;
  const [white, black]: Player[] = whiteUid === a.uid ? [a, b] : [b, a];
  return { gameId: ja.game_id as string, white, black, a, b };
}

const expectError = (p: Promise<unknown>, code: string) =>
  expect(p).rejects.toMatchObject({ data: code });

describe("matchmaking and moves", () => {
  test("two joiners share one game that starts with opposite colors", async () => {
    const t = newBackend();
    const a = await player(t, "alice");
    const first = await a.as.mutation(api.games.joinOnlineGame, { preset: "international" });
    expect(first.seat).toBe(0);
    expect((await a.as.query(api.games.get, { gameId: first.game_id }))!.status).toBe("waiting");

    const b = await player(t, "bob");
    const second = await b.as.mutation(api.games.joinOnlineGame, { preset: "international" });
    expect(second).toEqual({ game_id: first.game_id, seat: 1 });

    const game = (await a.as.query(api.games.get, { gameId: first.game_id }))!;
    expect(game.status).toBe("playing");
    expect(game.state.side).toBe("white");
    expect(new Set(game.game_players.map((p) => p.color))).toEqual(new Set(["white", "black"]));
    expect(game.turn_deadline_at).not.toBeNull();
  });

  test("players need a nickname", async () => {
    const t = newBackend();
    const anon = t.withIdentity({ subject: "nobody" });
    await anon.mutation(api.profiles.ensure, {});
    await expectError(anon.mutation(api.games.joinOnlineGame, { preset: "international" }), "profile_required");
  });

  test("move legality, turn order and stale plies are enforced", async () => {
    const t = newBackend();
    const { gameId, white, black } = await startedGame(t);

    await expectError(
      white.as.mutation(api.games.submitMove, {
        gameId,
        move: { from: 0, path: [5], captured: [] },
        expectedPly: 0,
      }),
      "illegal_move",
    );
    await expectError(
      black.as.mutation(api.games.submitMove, { gameId, move: WHITE_OPENING, expectedPly: 0 }),
      "not_your_turn",
    );
    expect(
      await white.as.mutation(api.games.submitMove, { gameId, move: WHITE_OPENING, expectedPly: 0 }),
    ).toEqual({ status: "ok", ply: 1 });
    expect(
      await black.as.mutation(api.games.submitMove, { gameId, move: BLACK_OPENING, expectedPly: 1 }),
    ).toEqual({ status: "ok", ply: 2 });
    await expectError(
      white.as.mutation(api.games.submitMove, {
        gameId,
        move: { from: 31, path: [27], captured: [] },
        expectedPly: 0,
      }),
      "stale_move",
    );
    const moves = await white.as.query(api.games.moves, { gameId });
    expect(moves.map((m) => m.ply)).toEqual([0, 1]);
  });

  test("resignation finishes the game and applies ELO", async () => {
    const t = newBackend();
    const { gameId, white, black } = await startedGame(t);
    expect(await white.as.mutation(api.games.resignGame, { gameId })).toEqual({ status: "resigned" });

    const game = (await white.as.query(api.games.get, { gameId }))!;
    expect(game.status).toBe("finished");
    expect(game.result).toBe("blackWin");
    expect(game.result_reason).toBe("resignation");
    expect(game.winner_uid).toBe(black.uid);
    const whiteSeat = game.game_players.find((p) => p.uid === white.uid)!;
    expect([whiteSeat.rating_before, whiteSeat.rating_after]).toEqual([1200, 1184]);

    const winner = (await black.as.query(api.profiles.get, { uid: black.uid }))!;
    expect([winner.rating, winner.rated_games, winner.wins]).toEqual([1216, 1, 1]);
    const loser = (await black.as.query(api.profiles.get, { uid: white.uid }))!;
    expect([loser.rating, loser.losses]).toEqual([1184, 1]);

    const board = await white.as.query(api.games.leaderboard, {});
    expect(board.map((r) => r.uid)).toEqual([]); // default needs 10 games
  });

  test("leaderboard honours leaderboard_min_games", async () => {
    const t = newBackend();
    await setConfig(t, { leaderboard_min_games: 1 });
    const { gameId, white, black } = await startedGame(t);
    await white.as.mutation(api.games.resignGame, { gameId });
    const board = await white.as.query(api.games.leaderboard, {});
    expect(board.map((r) => r.uid)).toEqual([black.uid, white.uid]);
  });

  test("leaving a lobby deletes the empty game", async () => {
    const t = newBackend();
    const a = await player(t, "alice");
    const { game_id } = await a.as.mutation(api.games.joinOnlineGame, { preset: "brazilian" });
    expect(await a.as.mutation(api.games.leaveGame, { gameId: game_id })).toEqual({ status: "left" });
    expect(await a.as.query(api.games.get, { gameId: game_id })).toBeNull();
  });
});

describe("clocks", () => {
  test("the per-move timer flags the side to move", async () => {
    vi.useFakeTimers();
    const t = newBackend();
    await setConfig(t, { turn_ms: 1000, bank_ms: 0 });
    const { gameId, white, black } = await startedGame(t);
    vi.advanceTimersByTime(1500);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    const game = (await white.as.query(api.games.get, { gameId }))!;
    expect(game.status).toBe("finished");
    expect(game.result_reason).toBe("timeout");
    expect(game.winner_uid).toBe(black.uid);
  });

  test("a move re-arms the timer and spends the bank", async () => {
    vi.useFakeTimers();
    const t = newBackend();
    await setConfig(t, { turn_ms: 1000, bank_ms: 5000 });
    const { gameId, white } = await startedGame(t);
    vi.advanceTimersByTime(3000);
    await white.as.mutation(api.games.submitMove, { gameId, move: WHITE_OPENING, expectedPly: 0 });
    const game = (await white.as.query(api.games.get, { gameId }))!;
    expect(game.white_bank_ms).toBe(3000);
    expect(game.status).toBe("playing");
    // The original timer must not flag white after the move.
    vi.advanceTimersByTime(2500);
    await t.finishInProgressScheduledFunctions();
    expect((await white.as.query(api.games.get, { gameId }))!.status).toBe("playing");
  });

  test("claim_timeout only applies once the deadline passed", async () => {
    vi.useFakeTimers();
    const t = newBackend();
    await setConfig(t, { turn_ms: 1000, bank_ms: 0 });
    const { gameId, black } = await startedGame(t);
    expect(await black.as.mutation(api.games.claimTimeout, { gameId })).toEqual({
      status: "not_expired",
    });
    vi.advanceTimersByTime(2000);
    expect(await black.as.mutation(api.games.claimTimeout, { gameId })).toEqual({
      status: "timeout_applied",
    });
  });
});

describe("draws, rematches, resume", () => {
  test("draw offer and acceptance", async () => {
    const t = newBackend();
    const { gameId, white, black } = await startedGame(t);
    expect(await white.as.mutation(api.games.offerDraw, { gameId })).toEqual({ status: "offered" });
    expect(await white.as.mutation(api.games.offerDraw, { gameId })).toEqual({
      status: "already_offered",
    });
    await expectError(
      white.as.mutation(api.games.respondDraw, { gameId, accept: true }),
      "cannot_respond_to_own_offer",
    );
    expect(await black.as.mutation(api.games.respondDraw, { gameId, accept: true })).toEqual({
      status: "draw_agreed",
    });
    const game = (await white.as.query(api.games.get, { gameId }))!;
    expect([game.result, game.result_reason]).toEqual(["draw", "agreement"]);
    const p = (await white.as.query(api.profiles.get, { uid: white.uid }))!;
    expect([p.rating, p.draws]).toEqual([1200, 1]);
  });

  test("rematch starts when both ask, colors swapped", async () => {
    const t = newBackend();
    const { gameId, white, black } = await startedGame(t);
    await white.as.mutation(api.games.resignGame, { gameId });
    expect(await white.as.mutation(api.games.requestRematch, { gameId })).toEqual({
      status: "requested",
    });
    const ready = await black.as.mutation(api.games.requestRematch, { gameId });
    expect(ready.status).toBe("ready");
    const rematch = (await white.as.query(api.games.get, { gameId: ready.game_id! }))!;
    expect(rematch.status).toBe("playing");
    expect(rematch.game_players.find((p) => p.uid === white.uid)!.color).toBe("black");
    expect(await white.as.mutation(api.games.requestRematch, { gameId })).toEqual(ready);
  });

  test("my_active_game resumes the live human game", async () => {
    const t = newBackend();
    const { gameId, white, black } = await startedGame(t);
    const mine = (await white.as.query(api.games.myActiveGame, {}))!;
    expect(mine.game_id).toBe(gameId);
    expect(mine.color).toBe("white");
    expect(mine.my_turn).toBe(true);
    expect(mine.opponent_nickname).toBe(black.name);
    await white.as.mutation(api.games.resignGame, { gameId });
    expect(await white.as.query(api.games.myActiveGame, {})).toBeNull();
  });

  test("recent games list, search and 'mine' filter", async () => {
    const t = newBackend();
    const { gameId, white } = await startedGame(t);
    await white.as.mutation(api.games.resignGame, { gameId });
    const outsider = await player(t, "carol");
    expect((await outsider.as.query(api.games.recent, {})).map((g) => g.id)).toEqual([gameId]);
    expect(await outsider.as.query(api.games.recent, { search: "ALI" })).toHaveLength(1);
    expect(await outsider.as.query(api.games.recent, { search: "zed" })).toHaveLength(0);
    expect(await outsider.as.query(api.games.recent, { mine: true })).toHaveLength(0);
    expect(await white.as.query(api.games.recent, { mine: true })).toHaveLength(1);
  });
});

describe("social games", () => {
  test("private invite accepted starts an unrated game", async () => {
    const t = newBackend();
    const a = await player(t, "alice");
    const b = await player(t, "bob");
    const { game_id, invite_id } = await a.as.mutation(api.social.createPrivateInvite, {
      inviteeUid: b.uid,
      preset: "american",
    });
    const invites = await b.as.query(api.social.myInvites, {});
    expect(invites.map((i) => [i.id, i.status, i.inviter_nickname])).toEqual([
      [invite_id, "pending", "alice"],
    ]);
    expect(await b.as.mutation(api.social.respondInvite, { inviteId: invite_id, accept: true })).toEqual({
      status: "accepted",
      game_id,
    });
    const game = (await a.as.query(api.games.get, { gameId: game_id }))!;
    expect([game.status, game.rated, game.is_private, game.board_size]).toEqual([
      "playing",
      false,
      true,
      8,
    ]);
    await expectError(
      a.as.mutation(api.social.createPrivateInvite, { inviteeUid: a.uid, preset: "american" }),
      "cannot_invite_self",
    );
  });

  test("share-link game joins once", async () => {
    const t = newBackend();
    const a = await player(t, "alice");
    const b = await player(t, "bob");
    const c = await player(t, "carol");
    const { game_id } = await a.as.mutation(api.social.createSocialGame, { preset: "international" });
    expect(await b.as.mutation(api.social.joinSocialGame, { gameId: game_id })).toEqual({
      status: "joined",
      game_id,
    });
    expect(await b.as.mutation(api.social.joinSocialGame, { gameId: game_id })).toEqual({
      status: "already_seated",
      game_id,
    });
    await expectError(c.as.mutation(api.social.joinSocialGame, { gameId: game_id }), "game_already_started");
  });

  test("available players excludes busy and stale players", async () => {
    const t = newBackend();
    const me = await player(t, "me");
    const idle = await player(t, "idle");
    const { white, black } = await startedGame(t);
    for (const p of [me, idle, white, black]) await p.as.mutation(api.presence.heartbeat, {});
    const list = await me.as.query(api.social.listAvailablePlayers, {});
    expect(list.map((r) => r.nickname)).toEqual(["idle"]);
    expect(await me.as.query(api.social.listAvailablePlayers, { search: "zz" })).toEqual([]);
  });
});

describe("PC games", () => {
  test("streamed PC game: moves, undo, abandonment of the previous one", async () => {
    const t = newBackend();
    const a = await player(t, "alice");
    const rules = { boardSize: 10, backwardCapture: true, flyingKing: true, majorityCapture: true };
    const { game_id } = await a.as.mutation(api.pcGames.start, {
      ...rules,
      aiLevel: "hard",
      allowUndo: true,
      humanColor: "white",
    });
    await a.as.mutation(api.pcGames.submitMove, { gameId: game_id, move: WHITE_OPENING, expectedPly: 0 });
    await a.as.mutation(api.pcGames.submitMove, { gameId: game_id, move: BLACK_OPENING, expectedPly: 1 });
    expect(await a.as.mutation(api.pcGames.undoMoves, { gameId: game_id, count: 2 })).toEqual({
      status: "ok",
      ply: 0,
    });
    const undone = (await a.as.query(api.games.get, { gameId: game_id }))!;
    expect([undone.state.ply, undone.last_move]).toEqual([0, null]);
    expect(undone.game_players.map((p) => [p.nickname, p.is_bot])).toEqual([
      ["alice", false],
      ["PC", true],
    ]);

    const next = await a.as.mutation(api.pcGames.start, {
      ...rules,
      aiLevel: "easy",
      allowUndo: false,
      humanColor: "black",
    });
    expect((await a.as.query(api.games.get, { gameId: game_id }))!.status).toBe("abandoned");
    await expectError(a.as.mutation(api.pcGames.undoMoves, { gameId: next.game_id, count: 1 }), "undo_not_allowed");
  });

  test("a PC win awards points once, by AI level", async () => {
    const t = newBackend();
    await setConfig(t, { points: { pc_hard_win: 7 } });
    const a = await player(t, "alice");
    const { game_id } = await a.as.mutation(api.pcGames.start, {
      boardSize: 8,
      backwardCapture: false,
      flyingKing: false,
      majorityCapture: false,
      aiLevel: "hard",
      allowUndo: false,
      humanColor: "white",
    });
    await t.run(async (ctx) => {
      await finishGame(ctx, game_id as Id<"games">, "whiteWin", "no_moves", "white");
      await finishGame(ctx, game_id as Id<"games">, "whiteWin", "no_moves", "white");
    });
    expect((await a.as.query(api.profiles.get, { uid: a.uid }))!.points).toBe(7);
    const board = await a.as.query(api.games.pointsLeaderboard, {});
    expect(board.map((r) => [r.nickname, r.points])).toEqual([["alice", 7]]);
    expect((await a.as.query(api.games.pointRules, {})).pc_hard_win).toBe(7);
  });

  test("idle PC games are abandoned by the sweep", async () => {
    vi.useFakeTimers();
    const t = newBackend();
    const a = await player(t, "alice");
    const { game_id } = await a.as.mutation(api.pcGames.start, {
      boardSize: 10,
      backwardCapture: true,
      flyingKing: true,
      majorityCapture: true,
      aiLevel: "easy",
      allowUndo: false,
      humanColor: "white",
    });
    vi.advanceTimersByTime(6 * 60_000);
    await t.mutation(internal.sweeps.onlineGames, {});
    expect((await a.as.query(api.games.get, { gameId: game_id }))!.status).toBe("abandoned");
  });
});

describe("watching and emotes", () => {
  test("watchers, emotes and the 2-second emote limit", async () => {
    vi.useFakeTimers();
    const t = newBackend();
    const { gameId, white } = await startedGame(t);
    const fan = await player(t, "fan");
    await fan.as.mutation(api.watch.heartbeat, { gameId });
    expect((await fan.as.query(api.watch.watchers, { gameId })).map((w) => w.nickname)).toEqual(["fan"]);

    await white.as.mutation(api.watch.sendEmote, { gameId, emoji: " 👍 " });
    await expectError(white.as.mutation(api.watch.sendEmote, { gameId, emoji: "👍" }), "too fast");
    await expectError(fan.as.mutation(api.watch.sendEmote, { gameId, emoji: "👍" }), "not a player of this game");
    vi.advanceTimersByTime(2500);
    await white.as.mutation(api.watch.sendEmote, { gameId, emoji: "🔥" });
    expect((await fan.as.query(api.watch.emotes, { gameId })).map((e) => e.emoji)).toEqual(["👍", "🔥"]);

    await fan.as.mutation(api.watch.unwatch, { gameId });
    expect(await fan.as.query(api.watch.watchers, { gameId })).toEqual([]);
  });

  test("stale watchers and presence are swept", async () => {
    vi.useFakeTimers();
    const t = newBackend();
    const { gameId } = await startedGame(t);
    const fan = await player(t, "fan");
    await fan.as.mutation(api.watch.heartbeat, { gameId });
    await fan.as.mutation(api.presence.heartbeat, {});
    vi.advanceTimersByTime(4 * 60_000);
    await t.mutation(internal.sweeps.onlineGames, {});
    expect(await fan.as.query(api.watch.watchers, { gameId })).toEqual([]);
    const presence = await t.run((ctx) => ctx.db.query("playerPresence").collect());
    expect(presence).toEqual([]);
  });
});

describe("blocks", () => {
  const device = { kind: "android_ssaid", value: "a1b2c3d4e5f6a7b8" };

  test("soft block stops play but not watching; full stops both", async () => {
    const t = newBackend();
    const { gameId } = await startedGame(t);
    const bad = await player(t, "bad");
    expect(await bad.as.mutation(api.blocks.syncDeviceBlocks, { devices: [device] })).toEqual({
      level: null,
    });

    await t.mutation(internal.blocks.blockPlayer, { uid: bad.uid as Id<"profiles">, level: "soft", days: 3 });
    const soft = await bad.as.mutation(api.blocks.syncDeviceBlocks, { devices: [] });
    expect([soft.level, soft.permanent]).toEqual(["soft", false]);
    await expectError(bad.as.mutation(api.games.joinOnlineGame, { preset: "international" }), "blocked");
    await bad.as.mutation(api.watch.heartbeat, { gameId });

    await t.mutation(internal.blocks.blockPlayer, { uid: bad.uid as Id<"profiles">, level: "full" });
    expect(await bad.as.mutation(api.blocks.syncDeviceBlocks, { devices: [] })).toEqual({
      level: "full",
      permanent: true,
      expires_at: null,
    });
    await expectError(bad.as.mutation(api.watch.heartbeat, { gameId }), "blocked");

    await t.mutation(internal.blocks.unblockPlayer, { uid: bad.uid as Id<"profiles"> });
    expect(await bad.as.mutation(api.blocks.syncDeviceBlocks, { devices: [] })).toEqual({ level: null });
  });

  test("a new account on a flagged device inherits the block", async () => {
    const t = newBackend();
    const bad = await player(t, "bad");
    await bad.as.mutation(api.blocks.syncDeviceBlocks, { devices: [device] });
    await t.mutation(internal.blocks.blockPlayer, { uid: bad.uid as Id<"profiles">, level: "full" });

    const alt = await player(t, "alt");
    const status = await alt.as.mutation(api.blocks.syncDeviceBlocks, { devices: [device] });
    expect(status.level).toBe("full");
    const ignored = await alt.as.mutation(api.blocks.syncDeviceBlocks, {
      devices: [{ kind: "android_ssaid", value: "9774d56d682e549c" }],
    });
    expect(ignored.level).toBe("full");
  });
});
