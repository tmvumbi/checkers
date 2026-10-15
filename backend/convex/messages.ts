import { query } from "./_generated/server";
import { currentProfile } from "./lib/auth";
import { iso } from "./lib/time";
import type { Doc } from "./_generated/dataModel";

// Admin → player messages (0014). Audience scoping happens here (enabled
// public rows + the caller's private rows); publish/expiry windows and the
// language filter stay client-side, as before.

export function messageRow(m: Doc<"playerMessages">) {
  return {
    id: m._id,
    type: m.type,
    language: m.language,
    target_uid: m.targetUid ?? null,
    html_text: m.htmlText ?? null,
    image_url: m.imageUrl ?? null,
    link_url: m.linkUrl ?? null,
    publish_at: iso(m.publishAt),
    expires_at: iso(m.expiresAt),
    enabled: m.enabled,
    created_at: iso(m.createdAt),
    updated_at: iso(m.updatedAt),
  };
}

export const mine = query({
  args: {},
  handler: async (ctx) => {
    const me = await currentProfile(ctx);
    if (!me) return [];
    const publicRows = await ctx.db
      .query("playerMessages")
      .withIndex("by_type_and_enabled", (q) => q.eq("type", "public").eq("enabled", true))
      .order("desc")
      .take(200);
    const privateRows = await ctx.db
      .query("playerMessages")
      .withIndex("by_target", (q) => q.eq("targetUid", me._id))
      .order("desc")
      .take(200);
    return [...publicRows, ...privateRows.filter((m) => m.enabled)].map(messageRow);
  },
});
