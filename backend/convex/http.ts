import { httpRouter } from "convex/server";
import { ConvexError } from "convex/values";
import { internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import { env, httpAction, type ActionCtx } from "./_generated/server";
import { DAY, utcDay } from "./lib/time";

// Admin console API at https://<deployment>.convex.site/admin/api/*.
// The checkers-admin Cloudflare Worker keeps serving the console page and
// its basic-auth gate, and forwards /admin/api/* here with
// `Authorization: Bearer <ADMIN_API_SECRET>`. Routes and JSON shapes match
// the PostgREST-backed handlers it replaced (scripts/admin_worker.js).

const http = httpRouter();
const PREFIX = "/admin/api/";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
const bad = (error: string) => json({ error }, 400);

function authorized(request: Request): boolean {
  const secret = env.ADMIN_API_SECRET;
  if (!secret) return false;
  const header = request.headers.get("Authorization") ?? "";
  const given = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (given.length !== secret.length) return false;
  let diff = 0;
  for (let i = 0; i < secret.length; i++) diff |= given.charCodeAt(i) ^ secret.charCodeAt(i);
  return diff === 0;
}

async function readJson(request: Request): Promise<Record<string, any>> {
  try {
    const body = await request.json();
    return body && typeof body === "object" && !Array.isArray(body) ? body : {};
  } catch {
    return {};
  }
}

function clampDays(raw: string | null, fallback: number) {
  const n = parseInt(raw ?? String(fallback), 10);
  return Math.min(Math.max(Number.isFinite(n) ? n : fallback, 1), 90);
}

function parseAudience(platformRaw: unknown, hoursRaw: unknown) {
  const platform = String(platformRaw ?? "all").toLowerCase();
  const hours =
    hoursRaw === null || hoursRaw === undefined || hoursRaw === "" ? null : parseInt(String(hoursRaw), 10);
  if (platform !== "all" && platform !== "android" && platform !== "ios") {
    throw new Error("platform must be all, android, or ios");
  }
  if (hours !== null && (!Number.isInteger(hours) || hours < 1 || hours > 87600)) {
    throw new Error("invalid activity window");
  }
  return { platform: platform as "all" | "android" | "ios", hours };
}

// ---------------------------------------------------------------------
// Settings (validation copied from the worker)
// ---------------------------------------------------------------------

function settingsView(config: Record<string, any>) {
  const ads = config.ads ?? {};
  const points = config.points ?? {};
  return {
    adsEnabled: ads.enabled ?? true,
    interstitialFrequency: ads.interstitialFrequency ?? 15,
    adUnits: {
      android: {
        banner: ads.android?.bannerAdUnitId ?? "",
        interstitial: ads.android?.interstitialAdUnitId ?? "",
      },
      ios: {
        banner: ads.ios?.bannerAdUnitId ?? "",
        interstitial: ads.ios?.interstitialAdUnitId ?? "",
      },
    },
    allowedAndroidVersions: config.allowed_android_versions ?? [],
    allowedIosVersions: config.allowed_ios_versions ?? [],
    androidAppUrl: config.android_app_url ?? "",
    iosAppUrl: config.ios_app_url ?? "",
    turnMs: config.turn_ms ?? 15000,
    bankMs: config.bank_ms ?? 300000,
    leaderboardMinGames: config.leaderboard_min_games ?? 1,
    pointRules: {
      pcEasyWin: points.pc_easy_win ?? 1,
      pcMediumWin: points.pc_medium_win ?? 5,
      pcHardWin: points.pc_hard_win ?? 10,
      tournamentPerParticipant: points.tournament_per_participant ?? 1,
      tournamentBonus: points.tournament_bonus ?? 0,
    },
  };
}

function validateSettings(b: Record<string, any>): string | null {
  const versionList = (value: unknown, label: string) => {
    if (!Array.isArray(value)) return `${label} must be a list`;
    for (const v of value) {
      if (typeof v !== "string" || !/^[0-9]+(\.[0-9]+)*$/.test(v.trim())) {
        return `${label}: "${v}" is not a version number`;
      }
    }
    return null;
  };
  const positiveInt = (value: unknown, label: string, min: number, max: number) =>
    !Number.isInteger(value) || (value as number) < min || (value as number) > max
      ? `${label} must be a whole number between ${min} and ${max}`
      : null;
  const httpsUrl = (value: unknown, label: string) =>
    typeof value !== "string" || !value.startsWith("https://") ? `${label} must be an https:// URL` : null;
  const p = b.pointRules;
  const checks = [
    b.allowedAndroidVersions !== undefined && versionList(b.allowedAndroidVersions, "Android versions"),
    b.allowedIosVersions !== undefined && versionList(b.allowedIosVersions, "iOS versions"),
    b.androidAppUrl !== undefined && httpsUrl(b.androidAppUrl, "Android app URL"),
    b.iosAppUrl !== undefined && httpsUrl(b.iosAppUrl, "iOS app URL"),
    b.turnMs !== undefined && positiveInt(b.turnMs, "Turn time", 3000, 600000),
    b.bankMs !== undefined && positiveInt(b.bankMs, "Time bank", 10000, 7200000),
    b.leaderboardMinGames !== undefined &&
      positiveInt(b.leaderboardMinGames, "Leaderboard minimum games", 0, 1000),
    b.interstitialFrequency !== undefined &&
      positiveInt(b.interstitialFrequency, "Interstitial frequency", 1, 1000),
    p !== undefined && (typeof p !== "object" || p === null || Array.isArray(p)) && "Point rules must be an object",
    p?.pcEasyWin !== undefined && positiveInt(p.pcEasyWin, "Easy PC win points", 0, 100000),
    p?.pcMediumWin !== undefined && positiveInt(p.pcMediumWin, "Medium PC win points", 0, 100000),
    p?.pcHardWin !== undefined && positiveInt(p.pcHardWin, "Hard PC win points", 0, 100000),
    p?.tournamentPerParticipant !== undefined &&
      positiveInt(p.tournamentPerParticipant, "Tournament points per participant", 0, 100000),
    p?.tournamentBonus !== undefined && positiveInt(p.tournamentBonus, "Tournament winner bonus", 0, 100000),
  ].filter(Boolean);
  return (checks[0] as string | undefined) ?? null;
}

function applySettings(config: Record<string, any>, b: Record<string, any>) {
  const ads = { ...(config.ads ?? {}) };
  if (b.adsEnabled != null) ads.enabled = b.adsEnabled;
  if (b.interstitialFrequency != null) ads.interstitialFrequency = b.interstitialFrequency;
  for (const platform of ["android", "ios"]) {
    const units = b.adUnits?.[platform];
    if (!units) continue;
    ads[platform] = {
      ...(ads[platform] ?? {}),
      ...(units.banner !== undefined ? { bannerAdUnitId: String(units.banner).trim() } : {}),
      ...(units.interstitial !== undefined ? { interstitialAdUnitId: String(units.interstitial).trim() } : {}),
    };
  }
  config.ads = ads;
  if (b.allowedAndroidVersions !== undefined) {
    config.allowed_android_versions = b.allowedAndroidVersions.map((v: string) => v.trim());
  }
  if (b.allowedIosVersions !== undefined) {
    config.allowed_ios_versions = b.allowedIosVersions.map((v: string) => v.trim());
  }
  if (b.androidAppUrl !== undefined) config.android_app_url = b.androidAppUrl.trim();
  if (b.iosAppUrl !== undefined) config.ios_app_url = b.iosAppUrl.trim();
  if (b.turnMs !== undefined) config.turn_ms = b.turnMs;
  if (b.bankMs !== undefined) config.bank_ms = b.bankMs;
  if (b.leaderboardMinGames !== undefined) config.leaderboard_min_games = b.leaderboardMinGames;
  if (b.pointRules !== undefined) {
    const points = { ...(config.points ?? {}) };
    const map: Record<string, string> = {
      pcEasyWin: "pc_easy_win",
      pcMediumWin: "pc_medium_win",
      pcHardWin: "pc_hard_win",
      tournamentPerParticipant: "tournament_per_participant",
      tournamentBonus: "tournament_bonus",
    };
    for (const [from, to] of Object.entries(map)) {
      if (b.pointRules[from] !== undefined) points[to] = b.pointRules[from];
    }
    config.points = points;
  }
  return config;
}

// ---------------------------------------------------------------------
// Metrics
// ---------------------------------------------------------------------

async function allGamesSince(ctx: ActionCtx, since: number) {
  const games = [];
  let cursor: string | null = null;
  for (;;) {
    const page: { games: any[]; isDone: boolean; continueCursor: string } = await ctx.runQuery(
      internal.admin.gamesPage,
      { since, cursor },
    );
    games.push(...page.games);
    if (page.isDone) return games;
    cursor = page.continueCursor;
  }
}

async function countAll(ctx: ActionCtx, table: "profiles" | "games" | "tournaments") {
  let total = 0;
  let cursor: string | null = null;
  for (;;) {
    const page: { counted: number; isDone: boolean; continueCursor: string } = await ctx.runQuery(
      internal.admin.countPage,
      { table, cursor },
    );
    total += page.counted;
    if (page.isDone) return total;
    cursor = page.continueCursor;
  }
}

async function playersPlayed(ctx: ActionCtx) {
  const uids = new Set<string>();
  let cursor: string | null = null;
  for (;;) {
    const page: { uids: string[]; isDone: boolean; continueCursor: string } = await ctx.runQuery(
      internal.admin.seatUidsPage,
      { cursor },
    );
    page.uids.forEach((u) => uids.add(u));
    if (page.isDone) return uids.size;
    cursor = page.continueCursor;
  }
}

function windowDays(days: number) {
  const out: string[] = [];
  for (let i = 0; i < days; i++) out.push(utcDay(Date.now() - i * DAY));
  return out; // newest first
}

const COUNTED = new Set(["playing", "finished", "abandoned"]);

async function opsMetrics(ctx: ActionCtx, days: number) {
  const dayList = windowDays(days);
  const since = Date.parse(`${dayList[dayList.length - 1]}T00:00:00Z`);
  const [games, snapshot, players, gamesTotal, tournamentsTotal, played] = await Promise.all([
    allGamesSince(ctx, since),
    ctx.runQuery(internal.admin.opsSnapshot, { since }),
    countAll(ctx, "profiles"),
    countAll(ctx, "games"),
    countAll(ctx, "tournaments"),
    playersPlayed(ctx),
  ]);
  const daily = dayList.map((day) => {
    const ofDay = games.filter((g) => utcDay(g.createdAt) === day);
    const active = new Set<string>();
    for (const g of ofDay) {
      if (!COUNTED.has(g.status)) continue;
      for (const s of g.seats) if (s.uid && !s.isBot) active.add(s.uid);
    }
    return {
      day,
      human_games: ofDay.filter((g) => !g.vsPc && COUNTED.has(g.status)).length,
      pc_games: ofDay.filter((g) => g.vsPc).length,
      tournaments: snapshot.tournamentsByDay.filter((d) => d === day).length,
      new_players: snapshot.newPlayersByDay.filter((d) => d === day).length,
      active_players: active.size,
    };
  });
  return {
    daily,
    totals: {
      players,
      players_played: played,
      games_total: gamesTotal,
      tournaments_total: tournamentsTotal,
    },
    now: snapshot.now,
  };
}

async function playerStats(ctx: ActionCtx, days: number, limit: number) {
  const dayList = windowDays(days);
  const fromDay = dayList[dayList.length - 1];
  const games = await allGamesSince(ctx, Date.parse(`${fromDay}T00:00:00Z`));
  type Agg = { total: number } & Record<string, number>;
  const agg = new Map<string, Agg>();
  for (const g of games) {
    if (!COUNTED.has(g.status)) continue;
    for (const s of g.seats) {
      if (!s.uid || s.isBot) continue;
      const outcome =
        g.result === "draw"
          ? "draw"
          : (g.result === "whiteWin" && s.color === "white") || (g.result === "blackWin" && s.color === "black")
            ? "won"
            : g.result === "whiteWin" || g.result === "blackWin"
              ? "lost"
              : "open";
      const a = agg.get(s.uid) ?? {
        total: 0,
        human_games: 0,
        human_won: 0,
        human_lost: 0,
        human_draw: 0,
        pc_games: 0,
        pc_won: 0,
        pc_lost: 0,
        pc_draw: 0,
      };
      const kind = g.vsPc ? "pc" : "human";
      a.total++;
      a[`${kind}_games`]++;
      if (outcome !== "open") a[`${kind}_${outcome}`]++;
      agg.set(s.uid, a);
    }
  }
  const top = [...agg.entries()]
    .sort((x, y) => y[1].total - x[1].total || x[0].localeCompare(y[0]))
    .slice(0, Math.min(Math.max(limit, 1), 500));
  const names: Record<string, { nickname: string; rating: number }> = await ctx.runQuery(
    internal.admin.profilesByIds,
    { ids: top.map(([uid]) => uid) },
  );
  return {
    players: top
      .map(([uid, a]) => ({
        uid,
        nickname: names[uid]?.nickname ?? "",
        rating: names[uid]?.rating ?? 1200,
        ...a,
      }))
      .sort((x, y) => y.total - x.total || x.nickname.localeCompare(y.nickname)),
    active_players: agg.size,
    from_day: fromDay,
  };
}

// ---------------------------------------------------------------------
// Push
// ---------------------------------------------------------------------

async function sendBroadcast(ctx: ActionCtx, b: Record<string, any>) {
  const title = String(b.title ?? "").trim();
  const body = String(b.body ?? "").trim();
  if (!title || title.length > 100) return bad("title must be between 1 and 100 characters");
  if (!body || body.length > 500) return bad("message must be between 1 and 500 characters");
  let audienceArgs;
  try {
    audienceArgs = parseAudience(b.platform, b.active_within_hours);
  } catch (error) {
    return bad((error as Error).message);
  }
  const audience = await ctx.runQuery(internal.admin.pushAudience, {
    platform: audienceArgs.platform,
    activeWithinHours: audienceArgs.hours,
  });
  if (audience.truncated) return bad("audience exceeds the 20,000-device safety limit");
  const url = env.PUSH_RELAY_URL;
  const key = env.PUSH_RELAY_KEY;
  if (!url || !key) return json({ error: "push relay is not configured" }, 502);

  const id: Id<"pushBroadcasts"> = await ctx.runMutation(internal.admin.createBroadcast, {
    title,
    body,
    platform: audienceArgs.platform,
    activeWithinHours: audienceArgs.hours,
    targeted: audience.devices,
  });
  let sent = 0;
  let failed = 0;
  try {
    for (let offset = 0; offset < audience.tokens.length; offset += 500) {
      const res = await fetch(url, {
        method: "POST",
        headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          tokens: audience.tokens.slice(offset, offset + 500),
          title,
          body,
          data: { type: "admin_broadcast", broadcast_id: id },
        }),
      });
      if (!res.ok) throw new Error(`push relay failed (${res.status})`);
      const result = (await res.json()) as { sent?: number; failed?: number };
      sent += result.sent ?? 0;
      failed += result.failed ?? 0;
    }
    const status = failed === 0 ? "sent" : sent > 0 ? "partial" : "failed";
    await ctx.runMutation(internal.admin.completeBroadcast, { id, sent, failed, status });
    return json({ id, targeted: audience.devices, sent, failed, status });
  } catch (error) {
    await ctx.runMutation(internal.admin.completeBroadcast, {
      id,
      sent,
      failed: Math.max(failed, audience.devices - sent),
      status: "failed",
      error: (error as Error).message.slice(0, 500),
    });
    return json({ error: (error as Error).message }, 502);
  }
}

// ---------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------

const handle = httpAction(async (ctx, request) => {
  if (!authorized(request)) return json({ error: "unauthorized" }, 401);
  const url = new URL(request.url);
  const path = "/" + url.pathname.slice(PREFIX.length).replace(/\/+$/, "");
  const [, resource, id] = path.split("/");
  const method = request.method;

  try {
    switch (`${method} /${resource}${id ? "/:id" : ""}`) {
      case "GET /customers":
        return json(await ctx.runQuery(internal.admin.listCustomers, {}));
      case "POST /customers": {
        const b = await readJson(request);
        if (!b.name) return bad("name is required");
        return json(
          await ctx.runMutation(internal.admin.createCustomer, {
            name: String(b.name),
            contact: b.contact ?? null,
            notes: b.notes ?? null,
          }),
          201,
        );
      }
      case "PATCH /customers/:id": {
        const b = await readJson(request);
        return json(
          await ctx.runMutation(internal.admin.updateCustomer, {
            id,
            ...(b.name !== undefined ? { name: String(b.name) } : {}),
            ...(b.contact !== undefined ? { contact: b.contact } : {}),
            ...(b.notes !== undefined ? { notes: b.notes } : {}),
          }),
        );
      }
      case "GET /campaigns":
        return json(await ctx.runQuery(internal.admin.listCampaigns, {}));
      case "POST /campaigns":
        return json(await ctx.runMutation(internal.admin.createCampaign, pickCampaign(await readJson(request))), 201);
      case "PATCH /campaigns/:id":
        return json(
          await ctx.runMutation(internal.admin.updateCampaign, {
            id,
            ...pickCampaign(await readJson(request)),
          }),
        );
      case "GET /stats":
        return json(
          await ctx.runQuery(internal.admin.adStats, {
            days: Math.min(parseInt(url.searchParams.get("days") ?? "30", 10) || 30, 90),
          }),
        );
      case "POST /upload": {
        const body = await request.blob();
        if (body.size > 4 * 1024 * 1024) return bad("file too large (max 4MB)");
        const type = request.headers.get("Content-Type") ?? "application/octet-stream";
        const storageId = await ctx.storage.store(new Blob([await body.arrayBuffer()], { type }));
        return json({ url: await ctx.storage.getUrl(storageId), storage_id: storageId });
      }
      case "GET /messages":
        return json(await ctx.runQuery(internal.admin.listMessages, {}));
      case "POST /messages": {
        const b = await readJson(request);
        return json(
          await ctx.runMutation(internal.admin.createMessage, {
            language: String(b.language ?? ""),
            target_uid: b.target_uid || null,
            html_text: b.html_text || null,
            image_url: b.image_url || null,
            link_url: b.link_url || null,
            days: parseInt(b.days, 10) || 30,
          }),
          201,
        );
      }
      case "PATCH /messages/:id": {
        const b = await readJson(request);
        return json(
          await ctx.runMutation(internal.admin.updateMessage, {
            id,
            ...(typeof b.enabled === "boolean" ? { enabled: b.enabled } : {}),
          }),
        );
      }
      case "GET /players":
        return json(
          await ctx.runQuery(internal.admin.searchPlayers, {
            search: url.searchParams.get("search") ?? "",
          }),
        );
      case "GET /blocks":
        return json(await ctx.runQuery(internal.admin.activeBlocks, {}));
      case "POST /blocks": {
        const b = await readJson(request);
        const uid = String(b.uid ?? "") as Id<"profiles">;
        return json(
          await ctx.runMutation(internal.blocks.blockPlayer, {
            uid,
            level: String(b.level ?? ""),
            days: b.days ?? null,
            reason: b.reason ?? null,
          }),
        );
      }
      case "POST /unblock": {
        const b = await readJson(request);
        return json(
          await ctx.runMutation(internal.blocks.unblockPlayer, {
            uid: String(b.uid ?? "") as Id<"profiles">,
          }),
        );
      }
      case "GET /ops":
        return json(await opsMetrics(ctx, clampDays(url.searchParams.get("days"), 7)));
      case "GET /player-stats":
        return json(await playerStats(ctx, clampDays(url.searchParams.get("days"), 7), 200));
      case "GET /push/:id": {
        if (id === "history") return json(await ctx.runQuery(internal.admin.pushHistory, {}));
        if (id !== "audience") break;
        let args;
        try {
          args = parseAudience(url.searchParams.get("platform"), url.searchParams.get("active_within_hours"));
        } catch (error) {
          return bad((error as Error).message);
        }
        const { tokens: _tokens, ...summary } = await ctx.runQuery(internal.admin.pushAudience, {
          platform: args.platform,
          activeWithinHours: args.hours,
        });
        return json(summary);
      }
      case "POST /push/:id":
        if (id !== "send") break;
        return await sendBroadcast(ctx, await readJson(request));
      case "GET /settings":
        return json(settingsView(await ctx.runQuery(internal.admin.getConfig, {})));
      case "PATCH /settings": {
        const b = await readJson(request);
        const error = validateSettings(b);
        if (error) return bad(error);
        const config = applySettings({ ...(await ctx.runQuery(internal.admin.getConfig, {})) }, b);
        return json(await ctx.runMutation(internal.admin.replaceConfig, { config }));
      }
      case "GET /gifts":
        return json(await ctx.runQuery(internal.giftsAdmin.list, {}));
      case "POST /gifts":
        return json(
          await ctx.runMutation(internal.giftsAdmin.create, { gift: pickGift(await readJson(request)) }),
          201,
        );
      case "PATCH /gifts/:id":
        return json(
          await ctx.runMutation(internal.giftsAdmin.update, { id, gift: pickGift(await readJson(request)) }),
        );
      case "DELETE /gifts/:id":
        return json(await ctx.runMutation(internal.giftsAdmin.remove, { id }));
      case "POST /gift-cancel/:id":
        return json(await ctx.runMutation(internal.giftsAdmin.cancel, { id }));
      case "POST /gift-delivered/:id": {
        const b = await readJson(request);
        return json(
          await ctx.runMutation(internal.giftsAdmin.markDelivered, {
            id,
            delivered: b.delivered !== false,
            note: typeof b.note === "string" ? b.note : null,
          }),
        );
      }
      case "GET /gift-bids/:id":
        return json(await ctx.runQuery(internal.giftsAdmin.bids, { id }));
      case "GET /feedback":
        return json(
          await ctx.runQuery(internal.admin.feedbackInbox, {
            scope: url.searchParams.get("scope") ?? "open",
          }),
        );
      case "PATCH /feedback/:id": {
        const b = await readJson(request);
        return json(await ctx.runMutation(internal.admin.markFeedback, { id, handled: !!b.handled }));
      }
    }
  } catch (error) {
    return json({ error: errorText(error) }, 400);
  }
  return json({ error: "not found" }, 404);
});

/** Readable text of a failed call: a ConvexError's data, else the message. */
function errorText(error: unknown): string {
  if (error instanceof ConvexError) return String(error.data);
  return (error as Error).message;
}

/** Gift editor payload, with types checked so bad input is a 400. */
function pickGift(b: Record<string, any>) {
  const out: Record<string, any> = {};
  const str = (k: string) => {
    if (b[k] === undefined) return;
    if (b[k] !== null && typeof b[k] !== "string") throw new ConvexError(`${k} must be text`);
    out[k] = b[k];
  };
  for (const k of ["name", "description", "ends_at"]) {
    str(k);
    if (out[k] === null) delete out[k];
  }
  str("youtube_url");
  str("customer_id");
  if (b.minimum_bid !== undefined) {
    const n = Number(b.minimum_bid);
    if (!Number.isFinite(n)) throw new ConvexError("minimum bid must be a number");
    out.minimum_bid = n;
  }
  if (b.active !== undefined) out.active = !!b.active;
  if (b.images !== undefined) {
    if (!Array.isArray(b.images)) throw new ConvexError("images must be a list");
    out.images = b.images.map((i: any) => ({
      url: String(i?.url ?? ""),
      storage_id: i?.storage_id ? String(i.storage_id) : null,
      width: Number(i?.width) || 0,
      height: Number(i?.height) || 0,
    }));
  }
  return out;
}

const CAMPAIGN_KEYS = [
  "name",
  "customer_id",
  "banner_url",
  "target_url",
  "piece_white_man_url",
  "piece_white_king_url",
  "piece_black_man_url",
  "piece_black_king_url",
  "starts_at",
  "ends_at",
  "active",
  "max_daily_prints",
] as const;

function pickCampaign(b: Record<string, any>) {
  const out: Record<string, any> = {};
  for (const key of CAMPAIGN_KEYS) if (b[key] !== undefined) out[key] = b[key];
  return out;
}

for (const method of ["GET", "POST", "PATCH", "DELETE"] as const) {
  http.route({ pathPrefix: PREFIX, method, handler: handle });
}

export default http;
