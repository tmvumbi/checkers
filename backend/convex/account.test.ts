import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { newBackend, player, type Backend } from "./test.setup";

afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

/** An imported Supabase profile, as the data migration writes it. */
async function importedProfile(
  t: Backend,
  legacyId: string,
  extra: { nickname?: string; rating?: number; google?: string } = {},
) {
  return await t.run(async (ctx) => {
    const now = Date.now();
    const id = await ctx.db.insert("profiles", {
      nickname: extra.nickname ?? "veteran",
      isAnonymous: !extra.google,
      rating: extra.rating ?? 1450,
      ratedGames: 40,
      wins: 30,
      losses: 10,
      draws: 0,
      points: 12,
      createdAt: now - 1e9,
      updatedAt: now - 1e9,
      legacyId,
    });
    if (extra.google) {
      await ctx.db.insert("legacyIdentities", { provider: "google", subject: extra.google, profileId: id });
    }
    return id;
  });
}

describe("account deletion", () => {
  test("resigns live games, anonymises history, removes the profile", async () => {
    const t = newBackend();
    const a = await player(t, "alice");
    const b = await player(t, "bob");
    await a.as.mutation(api.games.joinOnlineGame, { preset: "international" });
    const { game_id } = await b.as.mutation(api.games.joinOnlineGame, { preset: "international" });
    await a.as.mutation(api.presence.heartbeat, {});

    await a.as.mutation(api.account.deleteMine, {});

    const game = (await b.as.query(api.games.get, { gameId: game_id }))!;
    expect([game.status, game.result_reason, game.winner_uid]).toEqual(["finished", "resignation", b.uid]);
    expect(game.game_players.find((p) => p.uid === a.uid)!.nickname).toBe("Deleted player");
    expect(await b.as.query(api.profiles.get, { uid: a.uid })).toBeNull();
    expect(await t.run((ctx) => ctx.db.query("playerPresence").collect())).toEqual([]);
    expect(await a.as.query(api.profiles.me, {})).toBeNull();
  });
});

describe("Supabase account handoff", () => {
  beforeEach(() => {
    vi.stubEnv("SUPABASE_LEGACY_URL", "https://legacy.example");
    vi.stubEnv("SUPABASE_LEGACY_ANON_KEY", "anon");
  });

  test("a valid legacy session moves the imported profile to the caller", async () => {
    const t = newBackend();
    const legacyId = "11111111-1111-1111-1111-111111111111";
    const imported = await importedProfile(t, legacyId);
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string, init: RequestInit) => {
        expect(url).toBe("https://legacy.example/auth/v1/user");
        expect((init.headers as Record<string, string>).Authorization).toBe("Bearer old-token");
        return new Response(JSON.stringify({ id: legacyId }), { status: 200 });
      }),
    );
    // Fresh install: the new Firebase guest already got a placeholder.
    const guest = t.withIdentity({ subject: "firebase-guest" });
    const placeholder = await guest.mutation(api.profiles.ensure, {});

    const result = await guest.action(api.account.claimLegacy, { supabaseAccessToken: "old-token" });
    expect(result).toEqual({ status: "claimed", uid: imported });

    const me = (await guest.query(api.profiles.me, {}))!;
    expect([me.id, me.nickname, me.rating, me.points]).toEqual([imported, "veteran", 1450, 12]);
    expect(await guest.query(api.profiles.get, { uid: placeholder.id })).toBeNull();

    // Idempotent for the same caller, refused for anyone else.
    expect(await guest.action(api.account.claimLegacy, { supabaseAccessToken: "old-token" })).toEqual({
      status: "already_claimed",
      uid: imported,
    });
    const other = t.withIdentity({ subject: "someone-else" });
    expect(await other.action(api.account.claimLegacy, { supabaseAccessToken: "old-token" })).toEqual({
      status: "claimed_by_other",
    });
  });

  test("rejected sessions and active new accounts are refused", async () => {
    const t = newBackend();
    const legacyId = "22222222-2222-2222-2222-222222222222";
    await importedProfile(t, legacyId);
    vi.stubGlobal("fetch", vi.fn(async () => new Response("{}", { status: 401 })));
    const guest = t.withIdentity({ subject: "g" });
    expect(await guest.action(api.account.claimLegacy, { supabaseAccessToken: "bad" })).toEqual({
      status: "invalid_session",
    });

    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ id: legacyId }))));
    const busy = await player(t, "busy");
    const b = await player(t, "bob");
    await busy.as.mutation(api.games.joinOnlineGame, { preset: "international" });
    await b.as.mutation(api.games.joinOnlineGame, { preset: "international" });
    expect(await busy.as.action(api.account.claimLegacy, { supabaseAccessToken: "ok" })).toEqual({
      status: "current_account_in_use",
    });
  });

  test("Google sign-in re-claims the imported profile without a session", async () => {
    const t = newBackend();
    const imported = await importedProfile(t, "33333333-3333-3333-3333-333333333333", {
      google: "google-sub-42",
    });
    const user = t.withIdentity({
      subject: "firebase-uid",
      firebase: { sign_in_provider: "google.com", identities: { "google.com": ["google-sub-42"] } },
    } as never);
    const me = await user.mutation(api.profiles.ensure, {});
    expect([me.id, me.nickname, me.is_anonymous]).toEqual([imported, "veteran", false]);

    const stranger = t.withIdentity({
      subject: "other-uid",
      firebase: { sign_in_provider: "google.com", identities: { "google.com": ["google-sub-42"] } },
    } as never);
    expect((await stranger.mutation(api.profiles.ensure, {})).id).not.toBe(imported);
  });
});

describe("avatars", () => {
  test("upload, replace and remove", async () => {
    const t = newBackend();
    const a = await player(t, "alice");
    const first = await t.run((ctx) => ctx.storage.store(new Blob(["jpeg-1"], { type: "image/jpeg" })));
    const url = await a.as.mutation(api.profiles.setAvatar, { storageId: first });
    expect(url).toBeTruthy();
    expect((await a.as.query(api.profiles.me, {}))!.photo_url).toBe(url);

    const second = await t.run((ctx) => ctx.storage.store(new Blob(["jpeg-2"], { type: "image/jpeg" })));
    await a.as.mutation(api.profiles.setAvatar, { storageId: second });
    expect(await t.run((ctx) => ctx.storage.getUrl(first))).toBeNull();

    await a.as.mutation(api.profiles.removeAvatar, {});
    expect((await a.as.query(api.profiles.me, {}))!.photo_url).toBeNull();
    expect(await t.run((ctx) => ctx.storage.getUrl(second))).toBeNull();
  });

  test("oversized files are rejected", async () => {
    const t = newBackend();
    const a = await player(t, "alice");
    const big = new Uint8Array(2 * 1024 * 1024 + 1);
    const file = await t.run((ctx) => ctx.storage.store(new Blob([big], { type: "image/jpeg" })));
    await expect(a.as.mutation(api.profiles.setAvatar, { storageId: file })).rejects.toMatchObject({
      data: "invalid_avatar",
    });
  });
});

describe("messages and ads", () => {
  test("public + own private messages only", async () => {
    const t = newBackend();
    const a = await player(t, "alice");
    const b = await player(t, "bob");
    await t.mutation(internal.admin.createMessage, { language: "en", html_text: "hello all" });
    await t.mutation(internal.admin.createMessage, { language: "fr", html_text: "pour bob", target_uid: b.uid });
    expect((await a.as.query(api.messages.mine, {})).map((m) => m.html_text)).toEqual(["hello all"]);
    expect((await b.as.query(api.messages.mine, {})).map((m) => m.html_text).sort()).toEqual([
      "hello all",
      "pour bob",
    ]);
  });

  test("active ad respects window and daily cap; prints are counted", async () => {
    const t = newBackend();
    const a = await player(t, "alice");
    expect(await a.as.query(api.ads.getActive, {})).toBeNull();
    const [c] = await t.mutation(internal.admin.createCampaign, {
      name: "Sponsor",
      banner_url: "https://cdn/banner.png",
      target_url: "https://sponsor.example",
      piece_white_king_url: "https://cdn/wk.png",
      max_daily_prints: 2,
    });
    const ad = (await a.as.query(api.ads.getActive, {}))!;
    expect(ad).toEqual({
      id: c.id,
      banner_url: "https://cdn/banner.png",
      target_url: "https://sponsor.example",
      pieces: { white_king: "https://cdn/wk.png" },
    });
    await a.as.mutation(api.ads.recordPrint, { campaignId: c.id });
    await a.as.mutation(api.ads.recordClick, { campaignId: c.id });
    await a.as.mutation(api.ads.recordPrint, { campaignId: c.id });
    expect(await a.as.query(api.ads.getActive, {})).toBeNull();
    const stats = await t.query(internal.admin.adStats, { days: 1 });
    expect(stats.map((s) => [s.prints, s.clicks])).toEqual([[2, 1]]);
  });
});

describe("admin HTTP API", () => {
  const auth = { Authorization: "Bearer s3cret" };

  test("requires the shared secret", async () => {
    vi.stubEnv("ADMIN_API_SECRET", "s3cret");
    const t = newBackend();
    expect((await t.fetch("/admin/api/settings")).status).toBe(401);
    expect((await t.fetch("/admin/api/settings", { headers: { Authorization: "Bearer nope" } })).status).toBe(
      401,
    );
    expect((await t.fetch("/admin/api/settings", { headers: auth })).status).toBe(200);
  });

  test("settings round-trip with validation", async () => {
    vi.stubEnv("ADMIN_API_SECRET", "s3cret");
    const t = newBackend();
    const patch = (body: unknown) =>
      t.fetch("/admin/api/settings", {
        method: "PATCH",
        headers: { ...auth, "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
    expect((await patch({ turnMs: 5 })).status).toBe(400);
    expect(
      (await patch({ allowedAndroidVersions: ["2.0.0"], turnMs: 20000, pointRules: { pcHardWin: 12 } })).status,
    ).toBe(200);
    const view = await (await t.fetch("/admin/api/settings", { headers: auth })).json();
    expect([view.allowedAndroidVersions, view.turnMs, view.pointRules.pcHardWin]).toEqual([["2.0.0"], 20000, 12]);
    const a = await player(t, "alice");
    expect((await a.as.query(api.config.getPublic, {})).allowed_android_versions).toEqual(["2.0.0"]);
  });

  test("players, blocks, feedback, ops", async () => {
    vi.stubEnv("ADMIN_API_SECRET", "s3cret");
    const t = newBackend();
    const a = await player(t, "alice");
    await a.as.mutation(api.feedback.submit, { text: "great game" });

    const players = await (await t.fetch("/admin/api/players?search=ali", { headers: auth })).json();
    expect(players.map((p: { nickname: string }) => p.nickname)).toEqual(["alice"]);

    const block = await t.fetch("/admin/api/blocks", {
      method: "POST",
      headers: auth,
      body: JSON.stringify({ uid: a.uid, level: "soft", days: 2, reason: "spam" }),
    });
    expect(block.status).toBe(200);
    const blocks = await (await t.fetch("/admin/api/blocks", { headers: auth })).json();
    expect(blocks.map((b: { nickname: string; level: string }) => [b.nickname, b.level])).toEqual([
      ["alice", "soft"],
    ]);

    const inbox = await (await t.fetch("/admin/api/feedback", { headers: auth })).json();
    expect([inbox.open_count, inbox.items[0].text, inbox.items[0].nickname]).toEqual([1, "great game", "alice"]);
    await t.fetch(`/admin/api/feedback/${inbox.items[0].id}`, {
      method: "PATCH",
      headers: auth,
      body: JSON.stringify({ handled: true }),
    });
    expect((await (await t.fetch("/admin/api/feedback", { headers: auth })).json()).open_count).toBe(0);

    const ops = await (await t.fetch("/admin/api/ops?days=3", { headers: auth })).json();
    expect(ops.daily).toHaveLength(3);
    expect(ops.totals.players).toBe(1);
  });
});
