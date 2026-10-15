import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import { newBackend, player, type Backend } from "./test.setup";

// Port of scripts/test_tournament_flow.py and test_tournament_invite_flow.py.

afterEach(() => {
  vi.useRealTimers();
});

type P = Awaited<ReturnType<typeof player>>;

/** Runs jobs scheduled with runAfter(0) (bracket advance) without firing
 * the far-off clock timers. Requires fake timers. */
async function runScheduledNow(t: Backend) {
  vi.advanceTimersByTime(10);
  await t.finishInProgressScheduledFunctions();
}

async function lobbyOf(t: Backend, count: number) {
  const players: P[] = [];
  for (let i = 0; i < count; i++) {
    const p = await player(t, `p${i + 1}`);
    await p.as.mutation(api.tournaments.joinLobby, {});
    players.push(p);
  }
  return players;
}

/** Plays out every open match of the current stage: p1 wins by resignation
 * of p2 unless [loser] picks otherwise. */
async function playStage(
  t: Backend,
  players: P[],
  tournamentId: string,
  loser: (m: { p1_uid: string; p2_uid: string }) => string = (m) => m.p2_uid,
) {
  const detail = (await players[0].as.query(api.tournaments.detail, { tournamentId }))!;
  const open = detail.matches.filter((m) => m.status === "playing");
  for (const m of open) {
    const resigner = players.find((p) => p.uid === loser(m))!;
    await resigner.as.mutation(api.games.resignGame, { gameId: m.game_id! });
  }
  await runScheduledNow(t);
  return open;
}

describe("tournaments", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  test("lobby of 4 → semifinals → final + third place → ranks and points", async () => {
    const t = newBackend();
    await t.run(async (ctx) => {
      await ctx.db.insert("appConfig", {
        key: "public",
        config: { points: { tournament_per_participant: 2, tournament_bonus: 1 } },
      });
    });
    const players = await lobbyOf(t, 4);
    expect((await players[0].as.query(api.tournaments.lobby, {})).length).toBe(4);

    const started = await t.mutation(internal.tournaments.tryStart, {});
    expect(started).toMatchObject({ started: true, players: 4 });
    const tournamentId = (started as { tournament_id: string }).tournament_id;
    expect(await players[0].as.query(api.tournaments.lobby, {})).toEqual([]);

    let detail = (await players[0].as.query(api.tournaments.detail, { tournamentId }))!;
    expect([detail.tournament.status, detail.tournament.stage]).toEqual(["knockout", "sf"]);
    expect(detail.matches).toHaveLength(2);

    const state = await players[0].as.query(api.tournaments.myState, {});
    expect(state.tournament_id).toBe(tournamentId);
    expect(state.game_id).not.toBeNull();

    const semis = await playStage(t, players, tournamentId);
    detail = (await players[0].as.query(api.tournaments.detail, { tournamentId }))!;
    expect(detail.tournament.stage).toBe("f");
    const final = detail.matches.find((m) => m.stage === "f")!;
    const third = detail.matches.find((m) => m.stage === "third")!;
    expect([final.p1_uid, final.p2_uid]).toEqual(semis.map((m) => m.p1_uid));
    expect([third.p1_uid, third.p2_uid]).toEqual(semis.map((m) => m.p2_uid));

    await playStage(t, players, tournamentId);
    detail = (await players[0].as.query(api.tournaments.detail, { tournamentId }))!;
    expect(detail.tournament.status).toBe("finished");
    expect(detail.tournament.winner_uid).toBe(final.p1_uid);
    expect(detail.tournament.second_uid).toBe(final.p2_uid);
    expect(detail.tournament.third_uid).toBe(third.p1_uid);
    const rankOf = (uid: string) => detail.players.find((p) => p.uid === uid)!.final_rank;
    expect([final.p1_uid, final.p2_uid, third.p1_uid, third.p2_uid].map(rankOf)).toEqual([1, 2, 3, 4]);

    const champion = (await players[0].as.query(api.profiles.get, { uid: final.p1_uid }))!;
    expect(champion.points).toBe(4 * 2 + 1);
    const listed = await players[0].as.query(api.tournaments.list, {});
    expect(listed[0].winner_nickname).toBe(champion.nickname);
  });

  test("6 players play an elimination round, top 4 seeded 1v4 and 2v3", async () => {
    const t = newBackend();
    const players = await lobbyOf(t, 6);
    const started = (await t.mutation(internal.tournaments.tryStart, {})) as { tournament_id: string };
    const tournamentId = started.tournament_id;
    let detail = (await players[0].as.query(api.tournaments.detail, { tournamentId }))!;
    expect([detail.tournament.status, detail.tournament.stage]).toEqual(["elimination", "elimination"]);
    expect(detail.matches).toHaveLength(3);

    await playStage(t, players, tournamentId);
    detail = (await players[0].as.query(api.tournaments.detail, { tournamentId }))!;
    expect([detail.tournament.status, detail.tournament.stage]).toEqual(["knockout", "sf"]);
    const qualified = detail.players.filter((p) => !p.eliminated);
    expect(qualified).toHaveLength(4);
    // Three winners on 3 points, then the best loser by rating/join order.
    const standings = [...detail.players].sort(
      (a, b) => b.points - a.points || b.rating - a.rating || a.join_order - b.join_order,
    );
    const seeds = standings.slice(0, 4).map((p) => p.uid);
    const sf = detail.matches.filter((m) => m.stage === "sf").sort((a, b) => a.match_index - b.match_index);
    expect(sf.map((m) => [m.p1_uid, m.p2_uid])).toEqual([
      [seeds[0], seeds[3]],
      [seeds[1], seeds[2]],
    ]);
  });

  test("a knockout draw goes to the tiebreak", async () => {
    const t = newBackend();
    const players = await lobbyOf(t, 4);
    const { tournament_id } = (await t.mutation(internal.tournaments.tryStart, {})) as {
      tournament_id: string;
    };
    const detail = (await players[0].as.query(api.tournaments.detail, { tournamentId: tournament_id }))!;
    const m = detail.matches[0];
    const p1 = players.find((p) => p.uid === m.p1_uid)!;
    const p2 = players.find((p) => p.uid === m.p2_uid)!;
    await p1.as.mutation(api.games.offerDraw, { gameId: m.game_id! });
    await p2.as.mutation(api.games.respondDraw, { gameId: m.game_id!, accept: true });
    const after = (await players[0].as.query(api.tournaments.matches, { tournamentId: tournament_id }))!;
    const settled = after.find((x) => x.id === m.id)!;
    const joinOrder = (uid: string) => detail.players.find((p) => p.uid === uid)!.join_order;
    const expected = joinOrder(m.p1_uid) < joinOrder(m.p2_uid) ? m.p1_uid : m.p2_uid;
    expect([settled.status, settled.winner_uid]).toEqual(["finished", expected]);
  });

  test("fewer than 4 in the lobby does not start; stale members are pruned", async () => {
    const t = newBackend();
    await lobbyOf(t, 3);
    expect(await t.mutation(internal.tournaments.tryStart, {})).toEqual({ started: false, lobby: 3 });
    vi.advanceTimersByTime(60_000);
    await t.mutation(internal.tournaments.sweepLobby, {});
    expect(await t.run((ctx) => ctx.db.query("tournamentLobby").collect())).toEqual([]);
  });

  test("invites: eligibility, cooldown after decline, accept", async () => {
    const t = newBackend();
    const host = await player(t, "host");
    const guest = await player(t, "guest");
    const lobbyist = await player(t, "lobbyist");
    for (const p of [host, guest, lobbyist]) await p.as.mutation(api.presence.heartbeat, {});
    await lobbyist.as.mutation(api.tournaments.joinLobby, {});

    const invitable = await host.as.query(api.tournaments.listInvitablePlayers, {});
    expect(invitable.map((p) => p.nickname)).toEqual(["guest"]);

    expect(
      await host.as.mutation(api.tournaments.invite, { invitees: [guest.uid, lobbyist.uid, host.uid] }),
    ).toEqual({ sent: 1 });
    expect(await host.as.mutation(api.tournaments.invite, { invitees: [guest.uid] })).toEqual({ sent: 0 });

    const [invite] = await guest.as.query(api.tournaments.myInvites, {});
    expect(await guest.as.mutation(api.tournaments.respondInvite, { inviteId: invite.id, accept: false })).toEqual({
      status: "declined",
    });
    expect(await host.as.mutation(api.tournaments.invite, { invitees: [guest.uid] })).toEqual({ sent: 0 });
    expect(await host.as.query(api.tournaments.listInvitablePlayers, {})).toEqual([]);
  });

  test("reminder opt-ins are consumed unless the player is busy", async () => {
    const t = newBackend();
    const [a, b] = await lobbyOf(t, 2);
    await a.as.mutation(api.tournaments.leaveLobby, {});
    await a.as.mutation(api.tournaments.optInNotify, { token: "x".repeat(32) });
    await b.as.mutation(api.tournaments.optInNotify, { token: "y".repeat(32) });
    await t.mutation(internal.tournaments.notifySoon, {});
    const left = await t.run((ctx) => ctx.db.query("tournamentNotifyOptins").collect());
    // b is still in the lobby, so their opt-in waits; a's was consumed.
    expect(left.map((o) => o.uid)).toEqual([b.uid as Id<"profiles">]);
  });
});
