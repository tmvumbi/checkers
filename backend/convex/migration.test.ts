import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { newBackend, type Backend } from "./test.setup";

// A miniature Supabase export (rows shaped like json_agg output) run
// through the whole import pipeline.

const A = "aaaaaaaa-0000-0000-0000-000000000001";
const B = "bbbbbbbb-0000-0000-0000-000000000002";
const GONE = "dddddddd-0000-0000-0000-00000000dead";
const G1 = "11111111-1111-1111-1111-111111111111";
const G2 = "22222222-2222-2222-2222-222222222222";
const LIVE = "33333333-3333-3333-3333-333333333333";
const T1 = "44444444-4444-4444-4444-444444444444";
const BLOCK = "55555555-5555-5555-5555-555555555555";
const AVATAR = "https://api.dame.cd/storage/v1/object/public/avatars/a/avatar.jpg?v=1";

const iso = (s: string) => `${s}+00:00`;
const initialState = { board: [1, 1], side: "white", ply: 0, result: "ongoing", history: [] };

function exportRows() {
  const game = (id: string, extra: Record<string, unknown>) => ({
    id,
    status: "finished",
    preset: "international",
    board_size: 10,
    backward_capture: true,
    flying_king: true,
    majority_capture: true,
    is_private: false,
    allow_social_join: false,
    rated: true,
    host_uid: A,
    state: initialState,
    white_bank_ms: 300000,
    black_bank_ms: 300000,
    turn_started_at: null,
    turn_deadline_at: null,
    last_move: null,
    draw_offer_color: null,
    result: "whiteWin",
    result_reason: "resignation",
    winner_uid: A,
    rematch_requested_by: null,
    rematch_game_id: null,
    vs_pc: false,
    ai_level: null,
    allow_undo: false,
    tournament_id: null,
    created_at: iso("2026-09-01T10:00:00"),
    started_at: iso("2026-09-01T10:00:05"),
    finished_at: iso("2026-09-01T10:20:00"),
    updated_at: iso("2026-09-01T10:20:00"),
    ...extra,
  });
  const profile = (id: string, nickname: string, extra: Record<string, unknown> = {}) => ({
    id,
    nickname,
    photo_url: null,
    is_anonymous: true,
    rating: 1200,
    rated_games: 0,
    wins: 0,
    losses: 0,
    draws: 0,
    points: 0,
    created_at: iso("2026-08-20T09:00:00"),
    updated_at: iso("2026-08-20T09:00:00"),
    ...extra,
  });
  const seat = (gameId: string, s: number, uid: string, color: string, nickname: string) => ({
    game_id: gameId,
    seat: s,
    uid,
    nickname,
    photo_url: null,
    color,
    connected: true,
    last_seen_at: iso("2026-09-01T10:20:00"),
    rating_before: 1200,
    rating_after: 1216,
    is_bot: false,
  });
  return [
    ["app_config", { id: "public", config: { turn_ms: 15000, allowed_ios_versions: ["1.2.0"] } }],
    ["profiles", profile(A, "Alice", { rating: 1310, rated_games: 9, wins: 7, points: 15, photo_url: AVATAR, is_anonymous: false })],
    ["profiles", profile(B, "Bob", { rating: 1150 })],
    ["auth_identities", { user_id: A, provider: "google", subject: "google-sub-a" }],
    ["tournaments", {
      id: T1, number: 3, status: "finished", stage: "f", participant_count: 2, preset: "international",
      created_at: iso("2026-09-02T12:00:00"), finished_at: iso("2026-09-02T12:30:00"),
      winner_uid: A, second_uid: GONE, third_uid: null,
    }],
    ["games", game(G1, { rematch_game_id: G2 })],
    ["games", game(G2, { tournament_id: T1 })],
    ["games", game(LIVE, {
      status: "playing", result: null, result_reason: null, winner_uid: null, finished_at: null,
      turn_started_at: iso("2026-09-03T08:00:00"), turn_deadline_at: iso("2026-09-03T08:05:15"),
    })],
    ["game_players", seat(G1, 0, A, "white", "Alice")],
    ["game_players", seat(G1, 1, GONE, "black", "Deleted player")],
    ["game_players", seat(LIVE, 0, A, "white", "Alice")],
    ["game_players", seat(LIVE, 1, B, "black", "Bob")],
    ["game_moves", { game_id: G1, ply: 0, color: "white", move: { from: 30, path: [26], captured: [] }, ms_spent: 900, played_at: iso("2026-09-01T10:01:00") }],
    ["game_moves", { game_id: G1, ply: 1, color: "black", move: { from: 19, path: [23], captured: [] }, ms_spent: 700, played_at: iso("2026-09-01T10:01:30") }],
    ["game_emotes", { id: "e1", game_id: G1, uid: GONE, emoji: "👍", created_at: iso("2026-09-01T10:02:00") }],
    ["tournament_players", { tournament_id: T1, uid: A, nickname: "Alice", photo_url: null, rating: 1300, join_order: 1, points: 0, eliminated: false, final_rank: 1 }],
    ["tournament_matches", { id: "m1", tournament_id: T1, stage: "f", match_index: 1, p1_uid: A, p2_uid: GONE, game_id: G2, winner_uid: A, status: "finished", created_at: iso("2026-09-02T12:00:00") }],
    ["player_blocks", { id: BLOCK, uid: B, level: "soft", reason: "spam", expires_at: null, created_at: iso("2026-09-04T00:00:00"), revoked_at: null }],
    ["player_devices", { uid: B, kind: "android_ssaid", value: "abcdef0123456789", first_seen_at: iso("2026-09-04T00:00:00"), last_seen_at: iso("2026-09-04T00:00:00") }],
    ["blocked_devices", { id: "bd1", block_id: BLOCK, kind: "android_ssaid", value: "abcdef0123456789", level: "soft", expires_at: null }],
    ["point_awards", { id: 1, uid: A, award_type: "tournament_win", source_id: T1, points: 2, metadata: {}, created_at: iso("2026-09-02T12:30:00") }],
    ["feedback", { id: "f1", uid: B, text: "nice", created_at: iso("2026-09-05T00:00:00"), handled_at: null }],
    ["push_devices", { id: 7, uid: A, fcm_token: "t".repeat(40), platform: "ios", created_at: iso("2026-09-01T00:00:00"), last_seen_at: iso("2026-09-01T00:00:00"), disabled_at: null }],
  ] as const;
}

async function stage(t: Backend) {
  await t.run(async (ctx) => {
    for (const [table, row] of exportRows()) {
      await ctx.db.insert("migrationStaging", { table, row });
    }
  });
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-09-03T08:01:00Z"));
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string) => {
      if (url !== AVATAR) return new Response("missing", { status: 404 });
      return new Response(new Blob(["jpeg"], { type: "image/jpeg" }));
    }),
  );
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe("Supabase import", () => {
  test("rebuilds every table with remapped ids", async () => {
    const t = newBackend();
    await stage(t);
    await t.mutation(internal.migration.start, {});
    // Let the step chain run without firing the re-armed game clock.
    for (let i = 0; i < 80; i++) {
      vi.advanceTimersByTime(1);
      await t.finishInProgressScheduledFunctions();
    }
    const log = await t.query(internal.migration.status, {});
    expect(log.map((l) => l.step)).toContain("done");
    expect(log.find((l) => l.step === "files")!.detail).toEqual({ copied: 1, failed: [] });

    const { tables } = await t.action(internal.migration.verify, {});
    for (const [name, { staged, imported }] of Object.entries(tables)) {
      if (name === "profiles") expect(imported, name).toBe(staged + 1); // + tombstone
      else expect(imported, name).toBe(staged);
    }
    const tombstones = await t.run(async (ctx) =>
      (await ctx.db.query("profiles").collect()).filter((p) => p.nickname === ""),
    );
    expect(tombstones.map((p) => p.legacyId)).toEqual([GONE]);

    const ids = await t.run(async (ctx) => {
      const byLegacy = async (legacyId: string) =>
        (await ctx.db
          .query("games")
          .withIndex("by_legacy_id", (q) => q.eq("legacyId", legacyId))
          .unique())!;
      const alice = (await ctx.db
        .query("profiles")
        .withIndex("by_legacy_id", (q) => q.eq("legacyId", A))
        .unique())!;
      return { g1: await byLegacy(G1), g2: await byLegacy(G2), live: await byLegacy(LIVE), alice };
    });

    // Stats, photo moved to Convex storage, Google link recorded.
    expect([ids.alice.rating, ids.alice.points, ids.alice.isAnonymous]).toEqual([1310, 15, false]);
    expect(ids.alice.photoStorageId).toBeDefined();
    expect(ids.alice.photoUrl).not.toContain("api.dame.cd");

    // Game graph: rematch link, tournament link, seats, moves, search text.
    expect(ids.g1.rematchGameId).toBe(ids.g2._id);
    const g1 = (await t.query(api.games.get, { gameId: ids.g1._id }))!;
    expect(g1.winner_uid).toBe(ids.alice._id);
    expect(g1.game_players.map((p) => p.nickname)).toEqual(["Alice", "Deleted player"]);
    expect((await t.query(api.games.moves, { gameId: ids.g1._id })).map((m) => m.ply)).toEqual([0, 1]);
    expect(ids.g1.playerSearch).toBe("alice\ndeleted player");
    const tournament = (await t.query(api.tournaments.detail, { tournamentId: ids.g2.tournamentId! }))!;
    expect(tournament.matches[0].game_id).toBe(ids.g2._id);
    expect(tournament.tournament.winner_uid).toBe(ids.alice._id);

    // The live game kept its clock and got a flag-fall timer.
    expect(ids.live.status).toBe("playing");
    expect(ids.live.timeoutJobId).toBeDefined();
    vi.advanceTimersByTime(5 * 60_000);
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    const live = (await t.query(api.games.get, { gameId: ids.live._id }))!;
    expect([live.status, live.result_reason]).toEqual(["finished", "timeout"]);

    // Device block survives; the Google identity re-claims Alice.
    const bob = t.withIdentity({ subject: "new-bob" });
    const signedIn = t.withIdentity({
      subject: "firebase-alice",
      firebase: { sign_in_provider: "google.com", identities: { "google.com": ["google-sub-a"] } },
    } as never);
    expect((await signedIn.mutation(api.profiles.ensure, {})).id).toBe(ids.alice._id);
    await bob.mutation(api.profiles.ensure, {});
    const status = await bob.mutation(api.blocks.syncDeviceBlocks, {
      devices: [{ kind: "android_ssaid", value: "abcdef0123456789" }],
    });
    expect(status.level).toBe("soft");

    expect(await t.mutation(internal.migration.clearStaging, {})).toBe(exportRows().length);
  });

  test("refuses to import into a non-empty deployment", async () => {
    const t = newBackend();
    await stage(t);
    await t.run(async (ctx) => {
      await ctx.db.insert("profiles", {
        nickname: "x",
        isAnonymous: true,
        rating: 1200,
        ratedGames: 0,
        wins: 0,
        losses: 0,
        draws: 0,
        points: 0,
        createdAt: 0,
        updatedAt: 0,
      });
    });
    await expect(t.mutation(internal.migration.start, {})).rejects.toThrow(/not empty/);
  });
});
