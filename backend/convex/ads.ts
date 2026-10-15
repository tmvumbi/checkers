import { v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import { mutation, query, type MutationCtx } from "./_generated/server";
import { utcDay } from "./lib/time";

// Custom advertisement campaigns (0024).

/** `get_active_ad`: active, in its date window, under today's print cap;
 * the campaign with the fewest prints today first. */
export const getActive = query({
  args: {},
  handler: async (ctx) => {
    const today = utcDay(Date.now());
    const campaigns = await ctx.db
      .query("adCampaigns")
      .withIndex("by_active", (q) => q.eq("active", true))
      .take(200);
    let best: { c: Doc<"adCampaigns">; prints: number } | null = null;
    for (const c of campaigns) {
      if (c.startsAt > today || (c.endsAt && c.endsAt < today)) continue;
      const stats = await ctx.db
        .query("adDailyStats")
        .withIndex("by_campaign_and_day", (q) => q.eq("campaignId", c._id).eq("day", today))
        .unique();
      const prints = stats?.prints ?? 0;
      if (c.maxDailyPrints != null && prints >= c.maxDailyPrints) continue;
      if (
        !best ||
        prints < best.prints ||
        (prints === best.prints && c.createdAt < best.c.createdAt)
      ) {
        best = { c, prints };
      }
    }
    if (!best) return null;
    const c = best.c;
    const pieces: Record<string, string> = {};
    if (c.pieceWhiteManUrl) pieces.white_man = c.pieceWhiteManUrl;
    if (c.pieceWhiteKingUrl) pieces.white_king = c.pieceWhiteKingUrl;
    if (c.pieceBlackManUrl) pieces.black_man = c.pieceBlackManUrl;
    if (c.pieceBlackKingUrl) pieces.black_king = c.pieceBlackKingUrl;
    return { id: c._id, banner_url: c.bannerUrl, target_url: c.targetUrl, pieces };
  },
});

async function bump(ctx: MutationCtx, campaign: string, field: "prints" | "clicks") {
  const id = ctx.db.normalizeId("adCampaigns", campaign);
  if (!id || !(await ctx.db.get("adCampaigns", id))) return null;
  const day = utcDay(Date.now());
  const row = await ctx.db
    .query("adDailyStats")
    .withIndex("by_campaign_and_day", (q) => q.eq("campaignId", id as Id<"adCampaigns">).eq("day", day))
    .unique();
  if (row) await ctx.db.patch("adDailyStats", row._id, { [field]: row[field] + 1 });
  else {
    await ctx.db.insert("adDailyStats", {
      campaignId: id,
      day,
      prints: field === "prints" ? 1 : 0,
      clicks: field === "clicks" ? 1 : 0,
    });
  }
  return null;
}

export const recordPrint = mutation({
  args: { campaignId: v.string() },
  handler: async (ctx, { campaignId }) => await bump(ctx, campaignId, "prints"),
});

export const recordClick = mutation({
  args: { campaignId: v.string() },
  handler: async (ctx, { campaignId }) => await bump(ctx, campaignId, "clicks"),
});
