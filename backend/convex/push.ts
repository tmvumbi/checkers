import { v } from "convex/values";
import { env, internalAction, mutation } from "./_generated/server";
import { currentProfile, requireProfile } from "./lib/auth";
import { fail } from "./lib/errors";

// FCM device registry (0035) and the relay call to the checkers-push
// Cloudflare Worker, which holds the FCM service account.

export const registerDevice = mutation({
  args: { token: v.string(), platform: v.string() },
  handler: async (ctx, args) => {
    const me = await requireProfile(ctx);
    const platform = args.platform.toLowerCase();
    if (args.token.length < 20 || args.token.length > 4096) fail("bad_token");
    if (platform !== "android" && platform !== "ios") fail("bad_platform");
    const now = Date.now();
    const existing = await ctx.db
      .query("pushDevices")
      .withIndex("by_token", (q) => q.eq("fcmToken", args.token))
      .unique();
    if (existing) {
      await ctx.db.patch("pushDevices", existing._id, {
        uid: me._id,
        platform,
        lastSeenAt: now,
        disabledAt: undefined,
      });
    } else {
      await ctx.db.insert("pushDevices", {
        uid: me._id,
        fcmToken: args.token,
        platform,
        createdAt: now,
        lastSeenAt: now,
      });
    }
    return null;
  },
});

export const unregisterDevice = mutation({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    const me = await currentProfile(ctx);
    if (!me) return null;
    const row = await ctx.db
      .query("pushDevices")
      .withIndex("by_token", (q) => q.eq("fcmToken", token))
      .unique();
    if (row && row.uid === me._id) {
      await ctx.db.patch("pushDevices", row._id, { disabledAt: Date.now() });
    }
    return null;
  },
});

/** POSTs one batch (≤500 tokens) to the push relay. Best-effort. */
export const relay = internalAction({
  args: {
    tokens: v.array(v.string()),
    title: v.string(),
    body: v.string(),
    data: v.optional(v.record(v.string(), v.string())),
  },
  handler: async (_ctx, args) => {
    const url = env.PUSH_RELAY_URL;
    const key = env.PUSH_RELAY_KEY;
    if (!url || !key) return { sent: 0, failed: 0, skipped: true };
    let sent = 0;
    let failed = 0;
    for (let i = 0; i < args.tokens.length; i += 500) {
      const tokens = args.tokens.slice(i, i + 500);
      try {
        const res = await fetch(url, {
          method: "POST",
          headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
          body: JSON.stringify({ tokens, title: args.title, body: args.body, data: args.data ?? {} }),
        });
        const json = (await res.json().catch(() => ({}))) as { sent?: number; failed?: number };
        sent += json.sent ?? (res.ok ? tokens.length : 0);
        failed += json.failed ?? (res.ok ? 0 : tokens.length);
      } catch {
        failed += tokens.length;
      }
    }
    return { sent, failed, skipped: false };
  },
});
