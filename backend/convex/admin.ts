import { v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import { internalMutation, internalQuery, type MutationCtx } from "./_generated/server";
import { PUBLIC_CONFIG_KEY, publicConfig } from "./lib/config";
import { DAY, iso, utcDay } from "./lib/time";
import { messageRow } from "./messages";
import { PRESENCE_STALE_MS, WATCHER_STALE_MS } from "./social";

// Data access for the admin console (scripts/admin_worker.js). Only the
// /admin/api HTTP actions (http.ts) call these, after checking the shared
// ADMIN_API_SECRET. Rows keep the PostgREST shapes the console renders.

// ---------------------------------------------------------------------
// Row shapes
// ---------------------------------------------------------------------

function customerRow(c: Doc<"adCustomers">) {
  return {
    id: c._id,
    name: c.name,
    contact: c.contact ?? null,
    notes: c.notes ?? null,
    created_at: iso(c.createdAt),
  };
}

function campaignRow(c: Doc<"adCampaigns">, customer: Doc<"adCustomers"> | null) {
  return {
    id: c._id,
    customer_id: c.customerId ?? null,
    name: c.name,
    banner_url: c.bannerUrl,
    target_url: c.targetUrl,
    piece_white_man_url: c.pieceWhiteManUrl ?? null,
    piece_white_king_url: c.pieceWhiteKingUrl ?? null,
    piece_black_man_url: c.pieceBlackManUrl ?? null,
    piece_black_king_url: c.pieceBlackKingUrl ?? null,
    starts_at: c.startsAt,
    ends_at: c.endsAt ?? null,
    active: c.active,
    max_daily_prints: c.maxDailyPrints ?? null,
    created_at: iso(c.createdAt),
    ad_customers: customer ? { name: customer.name } : null,
  };
}

function broadcastRow(b: Doc<"pushBroadcasts">) {
  return {
    id: b._id,
    title: b.title,
    body: b.body,
    platform: b.platform,
    active_within_hours: b.activeWithinHours ?? null,
    targeted_count: b.targetedCount,
    sent_count: b.sentCount,
    failed_count: b.failedCount,
    status: b.status,
    error: b.error ?? null,
    created_at: iso(b.createdAt),
    completed_at: iso(b.completedAt),
  };
}

// Patch payload validators: snake_case like the console sends.
const nullableString = v.optional(v.union(v.string(), v.null()));
const campaignFields = {
  name: v.optional(v.string()),
  customer_id: nullableString,
  banner_url: v.optional(v.string()),
  target_url: v.optional(v.string()),
  piece_white_man_url: nullableString,
  piece_white_king_url: nullableString,
  piece_black_man_url: nullableString,
  piece_black_king_url: nullableString,
  starts_at: v.optional(v.string()),
  ends_at: nullableString,
  active: v.optional(v.boolean()),
  max_daily_prints: v.optional(v.union(v.number(), v.null())),
};

const opt = <T>(value: T | null | undefined) => (value === null ? undefined : value);

// ---------------------------------------------------------------------
// Customers and campaigns
// ---------------------------------------------------------------------

export const listCustomers = internalQuery({
  args: {},
  handler: async (ctx) => {
    const rows = await ctx.db.query("adCustomers").order("desc").take(500);
    return rows.sort((a, b) => b.createdAt - a.createdAt).map(customerRow);
  },
});

export const createCustomer = internalMutation({
  args: { name: v.string(), contact: nullableString, notes: nullableString },
  handler: async (ctx, a) => {
    const id = await ctx.db.insert("adCustomers", {
      name: a.name,
      contact: opt(a.contact),
      notes: opt(a.notes),
      createdAt: Date.now(),
    });
    return [customerRow((await ctx.db.get("adCustomers", id))!)];
  },
});

export const updateCustomer = internalMutation({
  args: { id: v.string(), name: v.optional(v.string()), contact: nullableString, notes: nullableString },
  handler: async (ctx, a) => {
    const id = ctx.db.normalizeId("adCustomers", a.id);
    if (!id) return [];
    const patch: Partial<Doc<"adCustomers">> = {};
    if (a.name !== undefined) patch.name = a.name;
    if (a.contact !== undefined) patch.contact = opt(a.contact);
    if (a.notes !== undefined) patch.notes = opt(a.notes);
    await ctx.db.patch("adCustomers", id, patch);
    return [customerRow((await ctx.db.get("adCustomers", id))!)];
  },
});

export const listCampaigns = internalQuery({
  args: {},
  handler: async (ctx) => {
    const rows = await ctx.db.query("adCampaigns").take(500);
    rows.sort((a, b) => b.createdAt - a.createdAt);
    return await Promise.all(
      rows.map(async (c) =>
        campaignRow(c, c.customerId ? await ctx.db.get("adCustomers", c.customerId) : null),
      ),
    );
  },
});

function campaignPatch(ctx: MutationCtx, a: Record<string, unknown>) {
  const patch: Partial<Doc<"adCampaigns">> = {};
  const str = (k: string) => a[k] as string | null | undefined;
  if (a.name !== undefined) patch.name = str("name")!;
  if (a.customer_id !== undefined) {
    patch.customerId = a.customer_id ? (ctx.db.normalizeId("adCustomers", str("customer_id")!) ?? undefined) : undefined;
  }
  if (a.banner_url !== undefined) patch.bannerUrl = str("banner_url")!;
  if (a.target_url !== undefined) patch.targetUrl = str("target_url")!;
  if (a.piece_white_man_url !== undefined) patch.pieceWhiteManUrl = opt(str("piece_white_man_url"));
  if (a.piece_white_king_url !== undefined) patch.pieceWhiteKingUrl = opt(str("piece_white_king_url"));
  if (a.piece_black_man_url !== undefined) patch.pieceBlackManUrl = opt(str("piece_black_man_url"));
  if (a.piece_black_king_url !== undefined) patch.pieceBlackKingUrl = opt(str("piece_black_king_url"));
  if (a.starts_at !== undefined) patch.startsAt = str("starts_at")!;
  if (a.ends_at !== undefined) patch.endsAt = opt(str("ends_at"));
  if (a.active !== undefined) patch.active = a.active as boolean;
  if (a.max_daily_prints !== undefined) patch.maxDailyPrints = opt(a.max_daily_prints as number | null);
  return patch;
}

export const createCampaign = internalMutation({
  args: campaignFields,
  handler: async (ctx, a) => {
    if (!a.name || !a.banner_url || !a.target_url) throw new Error("name, banner_url and target_url are required");
    const patch = campaignPatch(ctx, a);
    const id = await ctx.db.insert("adCampaigns", {
      name: a.name,
      bannerUrl: a.banner_url,
      targetUrl: a.target_url,
      startsAt: a.starts_at || utcDay(Date.now()),
      active: a.active ?? true,
      createdAt: Date.now(),
      ...patch,
    });
    const c = (await ctx.db.get("adCampaigns", id))!;
    return [campaignRow(c, c.customerId ? await ctx.db.get("adCustomers", c.customerId) : null)];
  },
});

export const updateCampaign = internalMutation({
  args: { id: v.string(), ...campaignFields },
  handler: async (ctx, { id: raw, ...a }) => {
    const id = ctx.db.normalizeId("adCampaigns", raw);
    if (!id) return [];
    await ctx.db.patch("adCampaigns", id, campaignPatch(ctx, a));
    const c = (await ctx.db.get("adCampaigns", id))!;
    return [campaignRow(c, c.customerId ? await ctx.db.get("adCustomers", c.customerId) : null)];
  },
});

export const adStats = internalQuery({
  args: { days: v.number() },
  handler: async (ctx, { days }) => {
    const since = utcDay(Date.now() - Math.min(Math.max(days, 1), 90) * DAY);
    const rows = await ctx.db
      .query("adDailyStats")
      .withIndex("by_day", (q) => q.gte("day", since))
      .order("desc")
      .take(5000);
    return rows.map((s) => ({ campaign_id: s.campaignId, day: s.day, prints: s.prints, clicks: s.clicks }));
  },
});

// ---------------------------------------------------------------------
// Messages, players, blocks
// ---------------------------------------------------------------------

export const listMessages = internalQuery({
  args: {},
  handler: async (ctx) => {
    const rows = await ctx.db.query("playerMessages").order("desc").take(200);
    return rows.sort((a, b) => b.createdAt - a.createdAt).slice(0, 50).map(messageRow);
  },
});

export const createMessage = internalMutation({
  args: {
    language: v.string(),
    target_uid: nullableString,
    html_text: nullableString,
    image_url: nullableString,
    link_url: nullableString,
    days: v.optional(v.union(v.number(), v.null())),
  },
  handler: async (ctx, a) => {
    if (a.language !== "en" && a.language !== "fr") throw new Error("language must be en or fr");
    if (!a.html_text && !a.image_url) throw new Error("text or an image is required");
    const target = a.target_uid ? ctx.db.normalizeId("profiles", a.target_uid) : null;
    if (a.target_uid && !target) throw new Error("unknown player");
    const now = Date.now();
    const id = await ctx.db.insert("playerMessages", {
      type: target ? "private" : "public",
      language: a.language,
      targetUid: target ?? undefined,
      htmlText: opt(a.html_text),
      imageUrl: opt(a.image_url),
      linkUrl: opt(a.link_url),
      publishAt: now,
      expiresAt: now + (a.days || 30) * DAY,
      enabled: true,
      createdAt: now,
      updatedAt: now,
    });
    return [messageRow((await ctx.db.get("playerMessages", id))!)];
  },
});

export const updateMessage = internalMutation({
  args: { id: v.string(), enabled: v.optional(v.boolean()) },
  handler: async (ctx, { id: raw, enabled }) => {
    const id = ctx.db.normalizeId("playerMessages", raw);
    if (!id) return [];
    if (enabled !== undefined) await ctx.db.patch("playerMessages", id, { enabled, updatedAt: Date.now() });
    return [messageRow((await ctx.db.get("playerMessages", id))!)];
  },
});

export const searchPlayers = internalQuery({
  args: { search: v.string() },
  handler: async (ctx, { search }) => {
    const needle = search.trim().toLowerCase();
    const out: { id: Id<"profiles">; nickname: string; rating: number }[] = [];
    let scanned = 0;
    for await (const p of ctx.db.query("profiles")) {
      if (++scanned > 20000 || out.length >= 200) break;
      if (p.nickname && p.nickname.toLowerCase().includes(needle)) {
        out.push({ id: p._id, nickname: p.nickname, rating: p.rating });
      }
    }
    return out.sort((a, b) => a.nickname.localeCompare(b.nickname)).slice(0, 20);
  },
});

export const activeBlocks = internalQuery({
  args: {},
  handler: async (ctx) => {
    const rows = await ctx.db.query("playerBlocks").order("desc").take(1000);
    const active = rows.filter((b) => b.revokedAt === undefined).slice(0, 100);
    return await Promise.all(
      active.map(async (b) => ({
        id: b._id,
        uid: b.uid,
        level: b.level,
        reason: b.reason ?? null,
        expires_at: iso(b.expiresAt),
        created_at: iso(b.createdAt),
        revoked_at: null,
        nickname: (await ctx.db.get("profiles", b.uid))?.nickname ?? "",
      })),
    );
  },
});

// ---------------------------------------------------------------------
// Settings (app_config.public)
// ---------------------------------------------------------------------

export const getConfig = internalQuery({
  args: {},
  handler: async (ctx) => await publicConfig(ctx),
});

export const replaceConfig = internalMutation({
  args: { config: v.any() },
  handler: async (ctx, { config }) => {
    const row = await ctx.db
      .query("appConfig")
      .withIndex("by_key", (q) => q.eq("key", PUBLIC_CONFIG_KEY))
      .unique();
    if (row) await ctx.db.patch("appConfig", row._id, { config });
    else await ctx.db.insert("appConfig", { key: PUBLIC_CONFIG_KEY, config });
    return [{ id: PUBLIC_CONFIG_KEY, config }];
  },
});

// ---------------------------------------------------------------------
// Feedback inbox
// ---------------------------------------------------------------------

export const feedbackInbox = internalQuery({
  args: { scope: v.string() },
  handler: async (ctx, { scope }) => {
    const rows = await ctx.db.query("feedback").withIndex("by_created").order("desc").take(1000);
    const open = rows.filter((f) => f.handledAt === undefined);
    const items = (scope === "all" ? rows : open).slice(0, 100);
    return {
      items: await Promise.all(
        items.map(async (f) => ({
          id: f._id,
          uid: f.uid,
          text: f.text,
          created_at: iso(f.createdAt),
          handled_at: iso(f.handledAt),
          nickname: (await ctx.db.get("profiles", f.uid))?.nickname ?? "",
        })),
      ),
      open_count: open.length,
    };
  },
});

export const markFeedback = internalMutation({
  args: { id: v.string(), handled: v.boolean() },
  handler: async (ctx, { id: raw, handled }) => {
    const id = ctx.db.normalizeId("feedback", raw);
    if (!id) return [];
    await ctx.db.patch("feedback", id, { handledAt: handled ? Date.now() : undefined });
    return [{ id }];
  },
});

// ---------------------------------------------------------------------
// Push broadcasts
// ---------------------------------------------------------------------

export const pushAudience = internalQuery({
  args: { platform: v.string(), activeWithinHours: v.union(v.number(), v.null()) },
  handler: async (ctx, { platform, activeWithinHours }) => {
    const since = activeWithinHours === null ? 0 : Date.now() - activeWithinHours * 3600_000;
    const tokens: string[] = [];
    const users = new Set<string>();
    const counts = { android: 0, ios: 0, unknown: 0 };
    let devices = 0;
    for await (const d of ctx.db
      .query("pushDevices")
      .withIndex("by_last_seen", (q) => q.gte("lastSeenAt", since))
      .order("desc")) {
      if (d.disabledAt !== undefined) continue;
      if (platform !== "all" && d.platform !== platform) continue;
      devices++;
      users.add(d.uid);
      counts[d.platform]++;
      if (tokens.length < 20000) tokens.push(d.fcmToken);
      if (devices > 25000) break;
    }
    return { tokens, devices, users: users.size, ...counts, truncated: devices > 20000 };
  },
});

export const pushHistory = internalQuery({
  args: {},
  handler: async (ctx) => {
    const rows = await ctx.db.query("pushBroadcasts").withIndex("by_created").order("desc").take(50);
    return rows.map(broadcastRow);
  },
});

export const createBroadcast = internalMutation({
  args: {
    title: v.string(),
    body: v.string(),
    platform: v.union(v.literal("all"), v.literal("android"), v.literal("ios")),
    activeWithinHours: v.union(v.number(), v.null()),
    targeted: v.number(),
  },
  handler: async (ctx, a) =>
    await ctx.db.insert("pushBroadcasts", {
      title: a.title,
      body: a.body,
      platform: a.platform,
      activeWithinHours: a.activeWithinHours ?? undefined,
      targetedCount: a.targeted,
      sentCount: 0,
      failedCount: 0,
      status: "sending",
      createdAt: Date.now(),
    }),
});

export const completeBroadcast = internalMutation({
  args: {
    id: v.id("pushBroadcasts"),
    sent: v.number(),
    failed: v.number(),
    status: v.union(v.literal("sent"), v.literal("partial"), v.literal("failed")),
    error: v.optional(v.string()),
  },
  handler: async (ctx, a) => {
    await ctx.db.patch("pushBroadcasts", a.id, {
      sentCount: a.sent,
      failedCount: a.failed,
      status: a.status,
      error: a.error,
      completedAt: Date.now(),
    });
    return null;
  },
});

// ---------------------------------------------------------------------
// Operations metrics (admin_operations_metrics / admin_player_stats)
// ---------------------------------------------------------------------

/** One page of games created since [since], with their seats. */
export const gamesPage = internalQuery({
  args: { since: v.number(), cursor: v.union(v.string(), v.null()) },
  handler: async (ctx, { since, cursor }) => {
    const page = await ctx.db
      .query("games")
      .withIndex("by_created", (q) => q.gte("createdAt", since))
      .paginate({ numItems: 500, cursor });
    const games = await Promise.all(
      page.page.map(async (g) => ({
        createdAt: g.createdAt,
        status: g.status,
        vsPc: g.vsPc,
        result: g.result ?? null,
        seats: (
          await ctx.db
            .query("gamePlayers")
            .withIndex("by_game_and_seat", (q) => q.eq("gameId", g._id))
            .take(2)
        ).map((s) => ({ uid: s.uid ?? null, color: s.color ?? null, isBot: s.isBot })),
      })),
    );
    return { games, isDone: page.isDone, continueCursor: page.continueCursor };
  },
});

/** Counts one page of a table (lifetime totals), plus distinct players. */
export const countPage = internalQuery({
  args: {
    table: v.union(v.literal("profiles"), v.literal("games"), v.literal("tournaments")),
    cursor: v.union(v.string(), v.null()),
  },
  handler: async (ctx, { table, cursor }) => {
    const page = await ctx.db.query(table).paginate({ numItems: 2000, cursor });
    let counted = 0;
    for (const doc of page.page) {
      if (table !== "games" || (doc as Doc<"games">).status !== "waiting") counted++;
    }
    return { counted, isDone: page.isDone, continueCursor: page.continueCursor };
  },
});

/** Daily new players/tournaments plus the realtime snapshot. */
export const opsSnapshot = internalQuery({
  args: { since: v.number() },
  handler: async (ctx, { since }) => {
    const now = Date.now();
    const newPlayers = await ctx.db
      .query("profiles")
      .withIndex("by_created", (q) => q.gte("createdAt", since))
      .take(20000);
    const tournaments = await ctx.db
      .query("tournaments")
      .withIndex("by_created", (q) => q.gte("createdAt", since))
      .take(5000);
    const connected = await ctx.db
      .query("playerPresence")
      .withIndex("by_last_active", (q) => q.gt("lastActiveAt", now - PRESENCE_STALE_MS))
      .take(5000);
    const players = [];
    for (const c of connected) {
      const seats = await ctx.db
        .query("gamePlayers")
        .withIndex("by_uid_and_status", (q) => q.eq("uid", c.uid).eq("gameStatus", "playing"))
        .take(5);
      let state = "idle";
      if (seats.length) {
        const games = await Promise.all(seats.map((s) => ctx.db.get("games", s.gameId)));
        state = games.some((g) => g?.vsPc) ? "pc" : "human";
      } else {
        const watching = await ctx.db
          .query("gameWatchers")
          .withIndex("by_uid", (q) => q.eq("uid", c.uid))
          .take(10);
        if (watching.some((w) => w.lastSeenAt > now - WATCHER_STALE_MS)) state = "watching";
      }
      players.push({ nickname: c.nickname, state });
    }
    const live = await ctx.db
      .query("games")
      .withIndex("by_status_and_started", (q) => q.eq("status", "playing"))
      .take(10000);
    const running = await ctx.db.query("tournaments").withIndex("by_status_and_created").take(1000);
    const lobby = await ctx.db.query("tournamentLobby").take(5000);
    return {
      newPlayersByDay: newPlayers.map((p) => utcDay(p.createdAt)),
      tournamentsByDay: tournaments.map((t) => utcDay(t.createdAt)),
      now: {
        connected: players.length,
        playing_human: players.filter((p) => p.state === "human").length,
        playing_pc: players.filter((p) => p.state === "pc").length,
        watching: players.filter((p) => p.state === "watching").length,
        idle: players.filter((p) => p.state === "idle").length,
        games_playing_human: live.filter((g) => !g.vsPc).length,
        games_playing_pc: live.filter((g) => g.vsPc).length,
        tournaments_running: running.filter((t) => t.status !== "finished").length,
        lobby_players: lobby.length,
        connected_players: players.sort((a, b) => a.nickname.localeCompare(b.nickname)),
      },
    };
  },
});

export const profilesByIds = internalQuery({
  args: { ids: v.array(v.string()) },
  handler: async (ctx, { ids }) => {
    const out: Record<string, { nickname: string; rating: number }> = {};
    for (const raw of ids) {
      const id = ctx.db.normalizeId("profiles", raw);
      const p = id ? await ctx.db.get("profiles", id) : null;
      if (p) out[raw] = { nickname: p.nickname, rating: p.rating };
    }
    return out;
  },
});

/** Every profile id that ever sat at a game (lifetime "players_played"). */
export const seatUidsPage = internalQuery({
  args: { cursor: v.union(v.string(), v.null()) },
  handler: async (ctx, { cursor }) => {
    const page = await ctx.db.query("gamePlayers").paginate({ numItems: 4000, cursor });
    const uids = [...new Set(page.page.flatMap((s) => (s.uid && !s.isBot ? [s.uid as string] : [])))];
    return { uids, isDone: page.isDone, continueCursor: page.continueCursor };
  },
});
