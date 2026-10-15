import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc, Id, TableNames } from "./_generated/dataModel";
import {
  env,
  internalAction,
  internalMutation,
  internalQuery,
  type MutationCtx,
} from "./_generated/server";
import { rearmTimeout, seatsOf } from "./lib/games";

// One-off import of the Supabase data (see backend/MIGRATION.md):
//   1. backend/scripts/export_supabase.py  → staging.jsonl
//   2. npx convex import --table migrationStaging --replace staging.jsonl
//   3. npx convex run migration:start
//   4. npx convex run migration:verify   (counts per table)
//   5. npx convex run migration:clearStaging
// Rows keep their Supabase key in `legacyId` where other rows point at
// them; foreign keys are remapped through those indexes. Referenced
// players without a profile row (deleted accounts, or users who never
// chose a nickname) become placeholder profiles with an empty nickname, so
// references stay valid; a returning user claiming one is asked for a
// nickname, and game history keeps its own nickname snapshots.

type Row = Record<string, any>;

const BATCH = 200;

const ts = (value: unknown): number | undefined =>
  typeof value === "string" && value ? Date.parse(value) : undefined;
const opt = <T>(value: T | null | undefined): T | undefined => (value === null ? undefined : value);
const num = (value: unknown, fallback = 0): number =>
  value === null || value === undefined ? fallback : Number(value);
const color = (value: unknown): "white" | "black" | undefined =>
  value === "white" || value === "black" ? value : undefined;

async function profileByLegacy(ctx: MutationCtx, legacy: unknown) {
  if (typeof legacy !== "string") return null;
  return await ctx.db
    .query("profiles")
    .withIndex("by_legacy_id", (q) => q.eq("legacyId", legacy))
    .unique();
}

/** Profile id for a Supabase uid, creating a placeholder when missing. */
async function uidFor(ctx: MutationCtx, legacy: unknown): Promise<Id<"profiles"> | undefined> {
  if (typeof legacy !== "string" || !legacy) return undefined;
  const existing = await profileByLegacy(ctx, legacy);
  if (existing) return existing._id;
  const now = Date.now();
  return await ctx.db.insert("profiles", {
    nickname: "",
    isAnonymous: true,
    rating: 1200,
    ratedGames: 0,
    wins: 0,
    losses: 0,
    draws: 0,
    points: 0,
    createdAt: now,
    updatedAt: now,
    legacyId: legacy,
  });
}

async function requiredUid(ctx: MutationCtx, legacy: unknown): Promise<Id<"profiles">> {
  const id = await uidFor(ctx, legacy);
  if (!id) throw new Error(`missing uid ${String(legacy)}`);
  return id;
}

async function gameFor(ctx: MutationCtx, legacy: unknown) {
  if (typeof legacy !== "string") return null;
  return await ctx.db
    .query("games")
    .withIndex("by_legacy_id", (q) => q.eq("legacyId", legacy))
    .unique();
}

async function tournamentFor(ctx: MutationCtx, legacy: unknown) {
  if (typeof legacy !== "string") return null;
  return await ctx.db
    .query("tournaments")
    .withIndex("by_legacy_id", (q) => q.eq("legacyId", legacy))
    .unique();
}

const TRANSFORMS: Record<string, (ctx: MutationCtx, r: Row) => Promise<unknown>> = {
  app_config: async (ctx, r) =>
    await ctx.db.insert("appConfig", { key: r.id, config: r.config ?? {} }),

  profiles: async (ctx, r) =>
    await ctx.db.insert("profiles", {
      nickname: r.nickname ?? "",
      photoUrl: opt(r.photo_url),
      isAnonymous: r.is_anonymous ?? true,
      rating: num(r.rating, 1200),
      ratedGames: num(r.rated_games),
      wins: num(r.wins),
      losses: num(r.losses),
      draws: num(r.draws),
      points: num(r.points),
      createdAt: ts(r.created_at) ?? Date.now(),
      updatedAt: ts(r.updated_at) ?? Date.now(),
      legacyId: r.id,
    }),

  auth_identities: async (ctx, r) => {
    const profile = await profileByLegacy(ctx, r.user_id);
    if (!profile || !r.subject) return;
    await ctx.db.insert("legacyIdentities", {
      provider: r.provider,
      subject: String(r.subject),
      profileId: profile._id,
    });
  },

  tournaments: async (ctx, r) =>
    await ctx.db.insert("tournaments", {
      number: num(r.number),
      status: r.status,
      stage: r.stage,
      participantCount: num(r.participant_count),
      preset: r.preset ?? "international",
      createdAt: ts(r.created_at) ?? Date.now(),
      finishedAt: ts(r.finished_at),
      winnerUid: await uidFor(ctx, r.winner_uid),
      secondUid: await uidFor(ctx, r.second_uid),
      thirdUid: await uidFor(ctx, r.third_uid),
      legacyId: r.id,
    }),

  games: async (ctx, r) =>
    await ctx.db.insert("games", {
      status: r.status,
      preset: r.preset,
      boardSize: num(r.board_size),
      backwardCapture: !!r.backward_capture,
      flyingKing: !!r.flying_king,
      majorityCapture: !!r.majority_capture,
      isPrivate: !!r.is_private,
      allowSocialJoin: !!r.allow_social_join,
      rated: r.rated ?? true,
      hostUid: await uidFor(ctx, r.host_uid),
      state: opt(r.state),
      whiteBankMs: num(r.white_bank_ms, 300000),
      blackBankMs: num(r.black_bank_ms, 300000),
      turnStartedAt: ts(r.turn_started_at),
      turnDeadlineAt: ts(r.turn_deadline_at),
      lastMove: opt(r.last_move),
      drawOfferColor: color(r.draw_offer_color),
      result: opt(r.result),
      resultReason: opt(r.result_reason),
      winnerUid: await uidFor(ctx, r.winner_uid),
      rematchRequestedBy: await uidFor(ctx, r.rematch_requested_by),
      vsPc: !!r.vs_pc,
      aiLevel: opt(r.ai_level),
      allowUndo: !!r.allow_undo,
      tournamentId: (await tournamentFor(ctx, r.tournament_id))?._id,
      createdAt: ts(r.created_at) ?? Date.now(),
      startedAt: ts(r.started_at),
      finishedAt: ts(r.finished_at),
      updatedAt: ts(r.updated_at) ?? Date.now(),
      legacyId: r.id,
    }),

  game_players: async (ctx, r) => {
    const game = await gameFor(ctx, r.game_id);
    if (!game) return;
    await ctx.db.insert("gamePlayers", {
      gameId: game._id,
      seat: num(r.seat),
      uid: await uidFor(ctx, r.uid),
      nickname: r.nickname ?? "",
      photoUrl: opt(r.photo_url),
      color: color(r.color),
      connected: r.connected ?? true,
      lastSeenAt: ts(r.last_seen_at) ?? Date.now(),
      ratingBefore: opt(r.rating_before),
      ratingAfter: opt(r.rating_after),
      isBot: !!r.is_bot,
      gameStatus: game.status,
    });
  },

  game_moves: async (ctx, r) => {
    const game = await gameFor(ctx, r.game_id);
    if (!game) return;
    await ctx.db.insert("gameMoves", {
      gameId: game._id,
      ply: num(r.ply),
      color: color(r.color) ?? "white",
      move: r.move,
      msSpent: num(r.ms_spent),
      playedAt: ts(r.played_at) ?? Date.now(),
    });
  },

  game_emotes: async (ctx, r) => {
    const game = await gameFor(ctx, r.game_id);
    if (!game) return;
    await ctx.db.insert("gameEmotes", {
      gameId: game._id,
      uid: await requiredUid(ctx, r.uid),
      emoji: r.emoji,
      createdAt: ts(r.created_at) ?? Date.now(),
    });
  },

  game_watchers: async (ctx, r) => {
    const game = await gameFor(ctx, r.game_id);
    if (!game) return;
    await ctx.db.insert("gameWatchers", {
      gameId: game._id,
      uid: await requiredUid(ctx, r.uid),
      nickname: r.nickname ?? "",
      photoUrl: opt(r.photo_url),
      rating: num(r.rating, 1200),
      joinedAt: ts(r.joined_at) ?? Date.now(),
      lastSeenAt: ts(r.last_seen_at) ?? Date.now(),
    });
  },

  invites: async (ctx, r) => {
    const game = await gameFor(ctx, r.game_id);
    if (!game) return;
    await ctx.db.insert("invites", {
      gameId: game._id,
      inviterUid: await requiredUid(ctx, r.inviter_uid),
      inviteeUid: await requiredUid(ctx, r.invitee_uid),
      inviterNickname: r.inviter_nickname ?? "",
      status: r.status,
      createdAt: ts(r.created_at) ?? Date.now(),
      expiresAt: ts(r.expires_at) ?? Date.now(),
    });
  },

  feedback: async (ctx, r) =>
    await ctx.db.insert("feedback", {
      uid: await requiredUid(ctx, r.uid),
      text: r.text,
      createdAt: ts(r.created_at) ?? Date.now(),
      handledAt: ts(r.handled_at),
    }),

  player_messages: async (ctx, r) =>
    await ctx.db.insert("playerMessages", {
      type: r.type,
      language: r.language,
      targetUid: await uidFor(ctx, r.target_uid),
      htmlText: opt(r.html_text),
      imageUrl: opt(r.image_url),
      linkUrl: opt(r.link_url),
      publishAt: ts(r.publish_at) ?? Date.now(),
      expiresAt: ts(r.expires_at) ?? Date.now(),
      enabled: !!r.enabled,
      createdAt: ts(r.created_at) ?? Date.now(),
      updatedAt: ts(r.updated_at) ?? Date.now(),
    }),

  player_blocks: async (ctx, r) =>
    await ctx.db.insert("playerBlocks", {
      uid: await requiredUid(ctx, r.uid),
      level: r.level,
      reason: opt(r.reason),
      expiresAt: ts(r.expires_at),
      createdAt: ts(r.created_at) ?? Date.now(),
      revokedAt: ts(r.revoked_at),
      legacyId: r.id,
    }),

  player_devices: async (ctx, r) =>
    await ctx.db.insert("playerDevices", {
      uid: await requiredUid(ctx, r.uid),
      kind: r.kind,
      value: r.value,
      firstSeenAt: ts(r.first_seen_at) ?? Date.now(),
      lastSeenAt: ts(r.last_seen_at) ?? Date.now(),
    }),

  blocked_devices: async (ctx, r) => {
    const block = await ctx.db
      .query("playerBlocks")
      .withIndex("by_legacy_id", (q) => q.eq("legacyId", r.block_id))
      .unique();
    if (!block) return;
    await ctx.db.insert("blockedDevices", {
      blockId: block._id,
      kind: r.kind,
      value: r.value,
      level: r.level,
      expiresAt: ts(r.expires_at),
    });
  },

  tournament_players: async (ctx, r) => {
    const tournament = await tournamentFor(ctx, r.tournament_id);
    if (!tournament) return;
    await ctx.db.insert("tournamentPlayers", {
      tournamentId: tournament._id,
      uid: await requiredUid(ctx, r.uid),
      nickname: r.nickname ?? "",
      photoUrl: opt(r.photo_url),
      rating: num(r.rating, 1200),
      joinOrder: num(r.join_order),
      points: num(r.points),
      eliminated: !!r.eliminated,
      finalRank: opt(r.final_rank),
    });
  },

  tournament_matches: async (ctx, r) => {
    const tournament = await tournamentFor(ctx, r.tournament_id);
    if (!tournament) return;
    await ctx.db.insert("tournamentMatches", {
      tournamentId: tournament._id,
      stage: r.stage,
      matchIndex: num(r.match_index),
      p1Uid: await requiredUid(ctx, r.p1_uid),
      p2Uid: await requiredUid(ctx, r.p2_uid),
      gameId: (await gameFor(ctx, r.game_id))?._id,
      winnerUid: await uidFor(ctx, r.winner_uid),
      status: r.status,
      createdAt: ts(r.created_at) ?? Date.now(),
    });
  },

  tournament_invites: async (ctx, r) =>
    await ctx.db.insert("tournamentInvites", {
      inviterUid: await requiredUid(ctx, r.inviter_uid),
      inviteeUid: await requiredUid(ctx, r.invitee_uid),
      inviterNickname: r.inviter_nickname ?? "",
      status: r.status,
      createdAt: ts(r.created_at) ?? Date.now(),
      expiresAt: ts(r.expires_at) ?? Date.now(),
      respondedAt: ts(r.responded_at),
    }),

  tournament_notify_optins: async (ctx, r) =>
    await ctx.db.insert("tournamentNotifyOptins", {
      uid: await requiredUid(ctx, r.uid),
      fcmToken: r.fcm_token,
      createdAt: ts(r.created_at) ?? Date.now(),
    }),

  ad_customers: async (ctx, r) =>
    await ctx.db.insert("adCustomers", {
      name: r.name,
      contact: opt(r.contact),
      notes: opt(r.notes),
      createdAt: ts(r.created_at) ?? Date.now(),
      legacyId: r.id,
    }),

  ad_campaigns: async (ctx, r) => {
    const customer = r.customer_id
      ? await ctx.db
          .query("adCustomers")
          .withIndex("by_legacy_id", (q) => q.eq("legacyId", r.customer_id))
          .unique()
      : null;
    await ctx.db.insert("adCampaigns", {
      customerId: customer?._id,
      name: r.name,
      bannerUrl: r.banner_url,
      targetUrl: r.target_url,
      pieceWhiteManUrl: opt(r.piece_white_man_url),
      pieceWhiteKingUrl: opt(r.piece_white_king_url),
      pieceBlackManUrl: opt(r.piece_black_man_url),
      pieceBlackKingUrl: opt(r.piece_black_king_url),
      startsAt: r.starts_at,
      endsAt: opt(r.ends_at),
      active: !!r.active,
      maxDailyPrints: opt(r.max_daily_prints),
      createdAt: ts(r.created_at) ?? Date.now(),
      legacyId: r.id,
    });
  },

  ad_daily_stats: async (ctx, r) => {
    const campaign = await ctx.db
      .query("adCampaigns")
      .withIndex("by_legacy_id", (q) => q.eq("legacyId", r.campaign_id))
      .unique();
    if (!campaign) return;
    await ctx.db.insert("adDailyStats", {
      campaignId: campaign._id,
      day: r.day,
      prints: num(r.prints),
      clicks: num(r.clicks),
    });
  },

  point_awards: async (ctx, r) => {
    const source =
      r.award_type === "pc_win"
        ? (await gameFor(ctx, r.source_id))?._id
        : (await tournamentFor(ctx, r.source_id))?._id;
    await ctx.db.insert("pointAwards", {
      uid: await requiredUid(ctx, r.uid),
      awardType: r.award_type,
      sourceId: source ?? `legacy:${r.source_id}`,
      points: num(r.points),
      metadata: r.metadata ?? {},
      createdAt: ts(r.created_at) ?? Date.now(),
    });
  },

  push_devices: async (ctx, r) =>
    await ctx.db.insert("pushDevices", {
      uid: await requiredUid(ctx, r.uid),
      fcmToken: r.fcm_token,
      platform: r.platform,
      createdAt: ts(r.created_at) ?? Date.now(),
      lastSeenAt: ts(r.last_seen_at) ?? Date.now(),
      disabledAt: ts(r.disabled_at),
    }),

  push_broadcasts: async (ctx, r) =>
    await ctx.db.insert("pushBroadcasts", {
      title: r.title,
      body: r.body,
      platform: r.platform,
      activeWithinHours: opt(r.active_within_hours),
      targetedCount: num(r.targeted_count),
      sentCount: num(r.sent_count),
      failedCount: num(r.failed_count),
      status: r.status,
      error: opt(r.error),
      createdAt: ts(r.created_at) ?? Date.now(),
      completedAt: ts(r.completed_at),
    }),
};

// Dependency order. Transient tables (presence, tournament lobby) are not
// carried over: clients re-create them within seconds.
const STEPS = [
  "app_config",
  "profiles",
  "auth_identities",
  "tournaments",
  "games",
  "game_players",
  "game_moves",
  "game_emotes",
  "game_watchers",
  "invites",
  "feedback",
  "player_messages",
  "player_blocks",
  "player_devices",
  "blocked_devices",
  "tournament_players",
  "tournament_matches",
  "tournament_invites",
  "tournament_notify_optins",
  "ad_customers",
  "ad_campaigns",
  "ad_daily_stats",
  "point_awards",
  "push_devices",
  "push_broadcasts",
] as const;

async function log(ctx: MutationCtx, step: string, detail: unknown) {
  await ctx.db.insert("migrationLog", { step, detail, at: Date.now() });
}

/** Kicks off the import. Refuses to run into a non-empty database. */
export const start = internalMutation({
  args: {},
  handler: async (ctx) => {
    if (await ctx.db.query("profiles").first()) {
      throw new Error("profiles is not empty: wipe the deployment first (migration:wipe)");
    }
    if (!(await ctx.db.query("migrationStaging").first())) {
      throw new Error("migrationStaging is empty: run the export and `npx convex import` first");
    }
    await log(ctx, "start", {});
    await ctx.scheduler.runAfter(0, internal.migration.runStep, { step: 0, cursor: null, done: 0 });
    return "scheduled — follow with `npx convex run migration:status`";
  },
});

export const runStep = internalMutation({
  args: { step: v.number(), cursor: v.union(v.string(), v.null()), done: v.number() },
  handler: async (ctx, { step, cursor, done }) => {
    const table = STEPS[step];
    if (!table) {
      await ctx.scheduler.runAfter(0, internal.migration.postProcess, { phase: 0, cursor: null });
      return;
    }
    const page = await ctx.db
      .query("migrationStaging")
      .withIndex("by_table", (q) => q.eq("table", table))
      .paginate({ numItems: BATCH, cursor });
    for (const staged of page.page) await TRANSFORMS[table](ctx, staged.row);
    const total = done + page.page.length;
    if (page.isDone) {
      await log(ctx, table, { imported: total });
      await ctx.scheduler.runAfter(0, internal.migration.runStep, { step: step + 1, cursor: null, done: 0 });
    } else {
      await ctx.scheduler.runAfter(0, internal.migration.runStep, {
        step,
        cursor: page.continueCursor,
        done: total,
      });
    }
  },
});

/**
 * After all rows exist: rematch links (games → games), recent-games search
 * text, and re-armed flag-fall timers for games still being played.
 */
export const postProcess = internalMutation({
  args: { phase: v.number(), cursor: v.union(v.string(), v.null()) },
  handler: async (ctx, { phase, cursor }) => {
    if (phase === 0) {
      const page = await ctx.db
        .query("migrationStaging")
        .withIndex("by_table", (q) => q.eq("table", "games"))
        .paginate({ numItems: BATCH, cursor });
      for (const staged of page.page) {
        const r = staged.row as Row;
        if (!r.rematch_game_id) continue;
        const game = await gameFor(ctx, r.id);
        const rematch = await gameFor(ctx, r.rematch_game_id);
        if (game && rematch) await ctx.db.patch("games", game._id, { rematchGameId: rematch._id });
      }
      return await next(ctx, phase, page);
    }
    if (phase === 1) {
      const page = await ctx.db.query("games").paginate({ numItems: BATCH, cursor });
      for (const game of page.page) {
        if (game.status !== "finished") continue;
        const seats = await seatsOf(ctx, game._id);
        await ctx.db.patch("games", game._id, {
          playerSearch: seats.map((s) => s.nickname.toLowerCase()).join("\n"),
        });
      }
      return await next(ctx, phase, page);
    }
    if (phase === 2) {
      const live = await ctx.db
        .query("games")
        .withIndex("by_status_and_started", (q) => q.eq("status", "playing"))
        .take(1000);
      for (const game of live) await rearmTimeout(ctx, game._id);
      await log(ctx, "post-process", { rearmed: live.filter((g) => !g.vsPc).length });
      await ctx.scheduler.runAfter(0, internal.migration.copyFiles, {});
    }
  },
});

async function next(
  ctx: MutationCtx,
  phase: number,
  page: { isDone: boolean; continueCursor: string },
) {
  await ctx.scheduler.runAfter(0, internal.migration.postProcess, {
    phase: page.isDone ? phase + 1 : phase,
    cursor: page.isDone ? null : page.continueCursor,
  });
}

// ---------------------------------------------------------------------
// Files: avatars and ad images move from Supabase storage to Convex.
// ---------------------------------------------------------------------

const SUPABASE_STORAGE = "/storage/v1/object/public/";

export const filesToCopy = internalQuery({
  args: {},
  handler: async (ctx) => {
    const out: { kind: string; id: string; field: string; url: string }[] = [];
    const legacy = (url: string | undefined) => !!url && url.includes(SUPABASE_STORAGE);
    for await (const p of ctx.db.query("profiles")) {
      if (legacy(p.photoUrl)) out.push({ kind: "profile", id: p._id, field: "photoUrl", url: p.photoUrl! });
    }
    for await (const c of ctx.db.query("adCampaigns")) {
      for (const field of [
        "bannerUrl",
        "pieceWhiteManUrl",
        "pieceWhiteKingUrl",
        "pieceBlackManUrl",
        "pieceBlackKingUrl",
      ] as const) {
        if (legacy(c[field])) out.push({ kind: "campaign", id: c._id, field, url: c[field]! });
      }
    }
    for await (const m of ctx.db.query("playerMessages")) {
      if (legacy(m.imageUrl)) out.push({ kind: "message", id: m._id, field: "imageUrl", url: m.imageUrl! });
    }
    return out;
  },
});

export const relinkFile = internalMutation({
  args: {
    kind: v.string(),
    id: v.string(),
    field: v.string(),
    storageId: v.id("_storage"),
  },
  handler: async (ctx, { kind, id, field, storageId }) => {
    const url = (await ctx.storage.getUrl(storageId)) ?? undefined;
    const table: TableNames = kind === "profile" ? "profiles" : kind === "campaign" ? "adCampaigns" : "playerMessages";
    const docId = ctx.db.normalizeId(table, id);
    if (!docId) return;
    await ctx.db.patch(table, docId as never, {
      [field]: url,
      ...(kind === "profile" ? { photoStorageId: storageId } : {}),
    } as never);
  },
});

export const copyFiles = internalAction({
  args: {},
  handler: async (ctx) => {
    const files = await ctx.runQuery(internal.migration.filesToCopy, {});
    let copied = 0;
    const failed: string[] = [];
    for (const file of files) {
      try {
        const res = await fetch(file.url);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const storageId = await ctx.storage.store(await res.blob());
        await ctx.runMutation(internal.migration.relinkFile, {
          kind: file.kind,
          id: file.id,
          field: file.field,
          storageId,
        });
        copied++;
      } catch (error) {
        failed.push(`${file.kind}:${file.id}:${(error as Error).message}`);
      }
    }
    await ctx.runMutation(internal.migration.finish, { copied, failed });
  },
});

export const finish = internalMutation({
  args: { copied: v.number(), failed: v.array(v.string()) },
  handler: async (ctx, args) => {
    await log(ctx, "files", args);
    await log(ctx, "done", {});
  },
});

// ---------------------------------------------------------------------
// Monitoring, verification, cleanup
// ---------------------------------------------------------------------

export const status = internalQuery({
  args: {},
  handler: async (ctx) => {
    const rows = await ctx.db.query("migrationLog").order("desc").take(100);
    return rows.reverse().map((r) => ({ step: r.step, detail: r.detail, at: new Date(r.at).toISOString() }));
  },
});

const TARGETS: Record<string, TableNames> = {
  app_config: "appConfig",
  profiles: "profiles",
  auth_identities: "legacyIdentities",
  tournaments: "tournaments",
  games: "games",
  game_players: "gamePlayers",
  game_moves: "gameMoves",
  game_emotes: "gameEmotes",
  game_watchers: "gameWatchers",
  invites: "invites",
  feedback: "feedback",
  player_messages: "playerMessages",
  player_blocks: "playerBlocks",
  player_devices: "playerDevices",
  blocked_devices: "blockedDevices",
  tournament_players: "tournamentPlayers",
  tournament_matches: "tournamentMatches",
  tournament_invites: "tournamentInvites",
  tournament_notify_optins: "tournamentNotifyOptins",
  ad_customers: "adCustomers",
  ad_campaigns: "adCampaigns",
  ad_daily_stats: "adDailyStats",
  point_awards: "pointAwards",
  push_devices: "pushDevices",
  push_broadcasts: "pushBroadcasts",
};

/** Counts one page of a table (or of one staged source table). */
export const countPage = internalQuery({
  args: {
    table: v.string(),
    staged: v.boolean(),
    cursor: v.union(v.string(), v.null()),
  },
  handler: async (ctx, { table, staged, cursor }) => {
    const page = staged
      ? await ctx.db
          .query("migrationStaging")
          .withIndex("by_table", (q) => q.eq("table", table))
          .paginate({ numItems: 4000, cursor })
      : await ctx.db.query(TARGETS[table]).paginate({ numItems: 4000, cursor });
    return { count: page.page.length, isDone: page.isDone, continueCursor: page.continueCursor };
  },
});

/** Staged vs imported row counts per table (profiles include tombstones
 * for referenced players that no longer existed). */
export const verify = internalAction({
  args: {},
  handler: async (ctx) => {
    const count = async (table: string, staged: boolean) => {
      let total = 0;
      let cursor: string | null = null;
      for (;;) {
        const page: { count: number; isDone: boolean; continueCursor: string } = await ctx.runQuery(
          internal.migration.countPage,
          { table, staged, cursor },
        );
        total += page.count;
        if (page.isDone) return total;
        cursor = page.continueCursor;
      }
    };
    const tables: Record<string, { staged: number; imported: number }> = {};
    for (const source of Object.keys(TARGETS)) {
      tables[source] = { staged: await count(source, true), imported: await count(source, false) };
    }
    return { tables };
  },
});

export const clearStaging = internalMutation({
  args: {},
  handler: async (ctx) => {
    const rows = await ctx.db.query("migrationStaging").take(4000);
    for (const row of rows) await ctx.db.delete("migrationStaging", row._id);
    if (rows.length === 4000) await ctx.scheduler.runAfter(0, internal.migration.clearStaging, {});
    return rows.length;
  },
});

/**
 * Rehearsal helper: deletes every application document and file so the
 * import can run again. Only on deployments with MIGRATION_ALLOW_WIPE=yes.
 */
export const wipe = internalMutation({
  args: {},
  handler: async (ctx) => {
    if (env.MIGRATION_ALLOW_WIPE !== "yes") {
      throw new Error("set MIGRATION_ALLOW_WIPE=yes on this deployment to allow wiping");
    }
    let deleted = 0;
    for (const table of [...new Set(Object.values(TARGETS))].concat(["playerPresence", "tournamentLobby", "migrationLog"] as TableNames[])) {
      const docs = await ctx.db.query(table).take(2000);
      for (const doc of docs as Doc<any>[]) {
        if (table === "profiles" && (doc as Doc<"profiles">).photoStorageId) {
          await ctx.storage.delete((doc as Doc<"profiles">).photoStorageId!);
        }
        await ctx.db.delete(table, doc._id as never);
        deleted++;
      }
      if (docs.length === 2000) {
        await ctx.scheduler.runAfter(0, internal.migration.wipe, {});
        return { deleted, more: true };
      }
    }
    return { deleted, more: false };
  },
});
