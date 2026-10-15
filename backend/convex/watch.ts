import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { currentProfile, requireProfile, DEFAULT_RATING } from "./lib/auth";
import { assertCanWatch } from "./lib/blocks";
import { fail } from "./lib/errors";
import { getGame } from "./lib/games";
import { emoteRow, watcherRow } from "./lib/serialize";

// Spectator presence and in-game emotes (0010, 0017).

/** `watch_heartbeat`: upserts the caller as a watcher of [gameId]. */
export const heartbeat = mutation({
  args: { gameId: v.string() },
  handler: async (ctx, { gameId }) => {
    const me = await requireProfile(ctx);
    const game = await getGame(ctx, gameId);
    if (!game) return null;
    await assertCanWatch(ctx, me._id);
    const now = Date.now();
    const existing = await ctx.db
      .query("gameWatchers")
      .withIndex("by_game_and_uid", (q) => q.eq("gameId", game._id).eq("uid", me._id))
      .unique();
    const fields = {
      nickname: me.nickname,
      photoUrl: me.photoUrl,
      rating: me.rating ?? DEFAULT_RATING,
      lastSeenAt: now,
    };
    if (existing) {
      await ctx.db.patch("gameWatchers", existing._id, fields);
    } else {
      await ctx.db.insert("gameWatchers", {
        gameId: game._id,
        uid: me._id,
        joinedAt: now,
        ...fields,
      });
    }
    return null;
  },
});

export const unwatch = mutation({
  args: { gameId: v.string() },
  handler: async (ctx, { gameId }) => {
    const me = await currentProfile(ctx);
    const id = ctx.db.normalizeId("games", gameId);
    if (!me || !id) return null;
    const row = await ctx.db
      .query("gameWatchers")
      .withIndex("by_game_and_uid", (q) => q.eq("gameId", id).eq("uid", me._id))
      .unique();
    if (row) await ctx.db.delete("gameWatchers", row._id);
    return null;
  },
});

/** Live watcher list of a game (oldest first). */
export const watchers = query({
  args: {
    gameId: v.string(),
    offset: v.optional(v.number()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("games", args.gameId);
    if (!id) return [];
    const offset = Math.max(Math.trunc(args.offset ?? 0), 0);
    const limit = Math.min(Math.max(Math.trunc(args.limit ?? 100), 1), 200);
    const rows = await ctx.db
      .query("gameWatchers")
      .withIndex("by_game_and_joined", (q) => q.eq("gameId", id))
      .take(offset + limit);
    return rows.slice(offset).map(watcherRow);
  },
});

/** `send_emote`: seated players of a live game, at most one per 2 s. */
export const sendEmote = mutation({
  args: { gameId: v.string(), emoji: v.string() },
  handler: async (ctx, args) => {
    const me = await requireProfile(ctx);
    const emoji = args.emoji.trim();
    const length = [...emoji].length;
    if (length < 1 || length > 8) fail("invalid emoji");
    const game = await getGame(ctx, args.gameId);
    if (!game || game.status !== "playing") fail("not a player of this game");
    const seat = await ctx.db
      .query("gamePlayers")
      .withIndex("by_game_and_uid", (q) => q.eq("gameId", game._id).eq("uid", me._id))
      .unique();
    if (!seat) fail("not a player of this game");

    const now = Date.now();
    const last = await ctx.db
      .query("gameEmotes")
      .withIndex("by_game_and_uid", (q) => q.eq("gameId", game._id).eq("uid", me._id))
      .order("desc")
      .first();
    if (last && last.createdAt > now - 2000) fail("too fast");
    await ctx.db.insert("gameEmotes", { gameId: game._id, uid: me._id, emoji, createdAt: now });
    return null;
  },
});

/** Emotes of a game in send order (latest 100). */
export const emotes = query({
  args: { gameId: v.string() },
  handler: async (ctx, { gameId }) => {
    const id = ctx.db.normalizeId("games", gameId);
    if (!id) return [];
    const rows = await ctx.db
      .query("gameEmotes")
      .withIndex("by_game", (q) => q.eq("gameId", id))
      .order("desc")
      .take(100);
    return rows.reverse().map(emoteRow);
  },
});
