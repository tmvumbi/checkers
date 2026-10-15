import { v } from "convex/values";
import { internal } from "./_generated/api";
import { env, internalAction, internalQuery, mutation } from "./_generated/server";
import { requireProfile } from "./lib/auth";
import { fail } from "./lib/errors";

// "Write to the admins" (0003 feedback table, 0011 Resend email trigger).

export const submit = mutation({
  args: { text: v.string() },
  handler: async (ctx, { text }) => {
    const me = await requireProfile(ctx);
    const trimmed = text.trim();
    if (trimmed.length === 0 || trimmed.length > 2000) fail("invalid_feedback");
    const id = await ctx.db.insert("feedback", { uid: me._id, text: trimmed, createdAt: Date.now() });
    await ctx.scheduler.runAfter(0, internal.feedback.sendEmail, { feedbackId: id });
    return null;
  },
});

export const emailPayload = internalQuery({
  args: { feedbackId: v.id("feedback") },
  handler: async (ctx, { feedbackId }) => {
    const row = await ctx.db.get("feedback", feedbackId);
    if (!row) return null;
    const profile = await ctx.db.get("profiles", row.uid);
    return {
      uid: row.uid,
      nickname: profile?.nickname ?? "",
      text: row.text,
      createdAt: row.createdAt,
    };
  },
});

/** Emails the admin through Resend; a no-op without RESEND_API_KEY. */
export const sendEmail = internalAction({
  args: { feedbackId: v.id("feedback") },
  handler: async (ctx, { feedbackId }) => {
    const key = env.RESEND_API_KEY;
    if (!key) return null;
    const payload = await ctx.runQuery(internal.feedback.emailPayload, { feedbackId });
    if (!payload) return null;
    const name = payload.nickname || "a player";
    try {
      await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          from: "Checkers <onboarding@resend.dev>",
          to: [env.FEEDBACK_EMAIL_TO ?? "tresormvumbi@gmail.com"],
          subject: `Checkers — message from ${name}`,
          text:
            `Player: ${payload.nickname || "(no nickname)"}\nUid: ${payload.uid}\n` +
            `Sent: ${new Date(payload.createdAt).toISOString()}\n\n${payload.text}`,
        }),
      });
    } catch {
      // Never let email problems surface; the feedback row is stored.
    }
    return null;
  },
});
