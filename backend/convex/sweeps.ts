import { internalMutation } from "./_generated/server";
import { abandonGame, deleteGameCascade, finishOnTime, seatsOf } from "./lib/games";
import { PRESENCE_STALE_MS, WATCHER_STALE_MS } from "./social";

// `sweep_online_games` (0010), minus the per-game flag fall, which now runs
// as a scheduled timer per move; the timeout pass here is only a backstop.

const PC_IDLE_MS = 5 * 60_000;
const WAITING_MAX_AGE_MS = 5 * 60_000;
const LOBBY_HEARTBEAT_MS = 60_000;
const BATCH = 200;

export const onlineGames = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = Date.now();

    const overdue = await ctx.db
      .query("games")
      .withIndex("by_status_and_deadline", (q) =>
        q.eq("status", "playing").lt("turnDeadlineAt", now - 5000),
      )
      .take(BATCH);
    for (const game of overdue) {
      if (!game.vsPc && game.turnDeadlineAt !== undefined) await finishOnTime(ctx, game);
    }

    const idlePc = await ctx.db
      .query("games")
      .withIndex("by_vs_pc_and_status_and_updated", (q) =>
        q.eq("vsPc", true).eq("status", "playing").lt("updatedAt", now - PC_IDLE_MS),
      )
      .take(BATCH);
    for (const game of idlePc) await abandonGame(ctx, game._id);

    const waiting = await ctx.db
      .query("games")
      .withIndex("by_status_and_private_and_preset", (q) => q.eq("status", "waiting"))
      .take(BATCH);
    for (const game of waiting) {
      if (game.createdAt >= now - WAITING_MAX_AGE_MS) continue;
      const seats = await seatsOf(ctx, game._id);
      if (!seats.some((s) => s.lastSeenAt > now - LOBBY_HEARTBEAT_MS)) {
        await deleteGameCascade(ctx, game._id);
      }
    }

    const watchers = await ctx.db
      .query("gameWatchers")
      .withIndex("by_last_seen", (q) => q.lt("lastSeenAt", now - WATCHER_STALE_MS))
      .take(BATCH);
    for (const w of watchers) await ctx.db.delete("gameWatchers", w._id);

    const presence = await ctx.db
      .query("playerPresence")
      .withIndex("by_last_active", (q) => q.lt("lastActiveAt", now - PRESENCE_STALE_MS))
      .take(BATCH);
    for (const p of presence) await ctx.db.delete("playerPresence", p._id);

    const expired = await ctx.db
      .query("invites")
      .withIndex("by_status_and_expires", (q) => q.eq("status", "pending").lt("expiresAt", now))
      .take(BATCH);
    for (const i of expired) await ctx.db.patch("invites", i._id, { status: "expired" });
    return null;
  },
});
