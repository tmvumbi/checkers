import { ConvexError, v } from "convex/values";
import { mutation, query } from "./_generated/server";

// Throwaway functions for the Phase 0 Flutter client spike (convex_flutter vs
// dartvex): auth round-trip, reactive subscription, mutation. Delete once the
// client is chosen.

export const whoami = query({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return null;
    return {
      subject: identity.subject,
      issuer: identity.issuer,
      name: identity.name ?? null,
      email: identity.email ?? null,
    };
  },
});

export const counter = query({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return null;
    const row = await ctx.db
      .query("spikeCounters")
      .withIndex("by_auth_subject", (q) => q.eq("authSubject", identity.subject))
      .unique();
    return { value: row?.value ?? 0, updated_at: row ? new Date(row.updatedAt).toISOString() : null };
  },
});

export const bump = mutation({
  args: { by: v.optional(v.number()) },
  handler: async (ctx, { by }) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new ConvexError({ code: "not_authenticated" });
    const row = await ctx.db
      .query("spikeCounters")
      .withIndex("by_auth_subject", (q) => q.eq("authSubject", identity.subject))
      .unique();
    const now = Date.now();
    if (row) {
      await ctx.db.patch(row._id, { value: row.value + (by ?? 1), updatedAt: now });
      return row.value + (by ?? 1);
    }
    await ctx.db.insert("spikeCounters", { authSubject: identity.subject, value: by ?? 1, updatedAt: now });
    return by ?? 1;
  },
});
