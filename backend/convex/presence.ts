import { v } from "convex/values";
import { mutation } from "./_generated/server";
import { currentProfile, requireProfile } from "./lib/auth";

// Online directory presence (0003 heartbeat_presence, 0026 leave_presence).
// Clients beat every 45 s while foregrounded; the sweep drops rows silent
// for 3 minutes.

export const heartbeat = mutation({
  args: { busyMode: v.optional(v.string()) },
  handler: async (ctx, { busyMode }) => {
    const me = await requireProfile(ctx);
    const fields = {
      nickname: me.nickname,
      photoUrl: me.photoUrl,
      rating: me.rating,
      busyMode: busyMode ?? "idle",
      lastActiveAt: Date.now(),
    };
    const row = await ctx.db
      .query("playerPresence")
      .withIndex("by_uid", (q) => q.eq("uid", me._id))
      .unique();
    if (row) await ctx.db.patch("playerPresence", row._id, fields);
    else await ctx.db.insert("playerPresence", { uid: me._id, ...fields });
    return null;
  },
});

export const leave = mutation({
  args: {},
  handler: async (ctx) => {
    const me = await currentProfile(ctx);
    if (!me) return null;
    const row = await ctx.db
      .query("playerPresence")
      .withIndex("by_uid", (q) => q.eq("uid", me._id))
      .unique();
    if (row) await ctx.db.delete("playerPresence", row._id);
    return null;
  },
});
