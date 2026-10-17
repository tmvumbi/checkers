import { paginationOptsValidator } from "convex/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, mutation, query, type QueryCtx } from "./_generated/server";
import { currentProfile, requirePlayer } from "./lib/auth";
import { assertNotBlockedForPlay } from "./lib/blocks";
import { fail } from "./lib/errors";
import {
  bidOf,
  bidRow,
  evaluateGiftBid,
  movePoints,
  notifyOutbid,
  publicGiftRow,
  resolveExpiredGift,
} from "./lib/gifts";

// Gift store for the dame.cd website: players sign in there with the same
// Google/Apple account as in the app and bid their points. Reads are open
// to everyone; bidding needs a non-guest profile created by the app.

async function offeredBy(ctx: QueryCtx, gift: Doc<"gifts">) {
  if (!gift.customerId) return null;
  return (await ctx.db.get("adCustomers", gift.customerId))?.name ?? null;
}

/** Active open auctions, ending soonest first. */
export const listOpen = query({
  args: {},
  handler: async (ctx) => {
    const gifts = await ctx.db
      .query("gifts")
      .withIndex("by_active_and_status_and_endsAt", (q) => q.eq("active", true).eq("status", "open"))
      .take(100);
    return await Promise.all(gifts.map(async (g) => publicGiftRow(g, await offeredBy(ctx, g))));
  },
});

/** One active gift, plus the caller's bid on it when signed in. */
export const get = query({
  args: { id: v.string() },
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("gifts", args.id);
    const gift = id ? await ctx.db.get("gifts", id) : null;
    if (!gift || !gift.active) return null;
    const me = await currentProfile(ctx);
    const mine = me ? await bidOf(ctx, gift._id, me._id) : null;
    return {
      ...publicGiftRow(gift, await offeredBy(ctx, gift)),
      leader_is_me: me !== null && gift.highestBidderUid === me._id,
      my_bid: mine ? bidRow(mine) : null,
    };
  },
});

/** Finished auctions with a winner, most recent first. */
export const winners = query({
  args: { paginationOpts: paginationOptsValidator },
  handler: async (ctx, args) => {
    const page = await ctx.db
      .query("gifts")
      .withIndex("by_active_and_status_and_closedAt", (q) => q.eq("active", true).eq("status", "closed"))
      .order("desc")
      .paginate(args.paginationOpts);
    return {
      ...page,
      page: await Promise.all(page.page.map(async (g) => publicGiftRow(g, await offeredBy(ctx, g)))),
    };
  },
});

/** The signed-in player as the website shows them (null = no app profile). */
export const me = query({
  args: {},
  handler: async (ctx) => {
    const me = await currentProfile(ctx);
    if (!me) return null;
    return {
      id: me._id,
      nickname: me.nickname,
      photo_url: me.photoUrl ?? null,
      points: me.points,
      is_anonymous: me.isAnonymous,
    };
  },
});

/** The caller's live bids (leading or outbid), ending soonest first. */
export const myBids = query({
  args: {},
  handler: async (ctx) => {
    const me = await currentProfile(ctx);
    if (!me) return [];
    const rows: Doc<"giftBids">[] = [];
    for (const status of ["leading", "outbid"] as const) {
      rows.push(
        ...(await ctx.db
          .query("giftBids")
          .withIndex("by_uid_and_status_and_giftEndsAt", (q) => q.eq("uid", me._id).eq("status", status))
          .take(100)),
      );
    }
    return rows.sort((a, b) => a.giftEndsAt - b.giftEndsAt).map(bidRow);
  },
});

/** Gifts the caller won, most recent first. */
export const myWins = query({
  args: { paginationOpts: paginationOptsValidator },
  handler: async (ctx, args) => {
    const me = await currentProfile(ctx);
    if (!me) return { page: [], isDone: true, continueCursor: "" };
    const page = await ctx.db
      .query("giftBids")
      .withIndex("by_uid_and_status_and_updatedAt", (q) => q.eq("uid", me._id).eq("status", "won"))
      .order("desc")
      .paginate(args.paginationOpts);
    return { ...page, page: page.page.map(bidRow) };
  },
});

/**
 * Places or raises a bid. Retrying with the same [clientBidId] after a
 * lost response is a no-op, so a flaky connection never charges twice.
 */
export const placeBid = mutation({
  args: {
    giftId: v.string(),
    amount: v.number(),
    clientBidId: v.string(),
    language: v.union(v.literal("en"), v.literal("fr")),
  },
  handler: async (ctx, args) => {
    const me = await requirePlayer(ctx);
    if (me.isAnonymous) fail("anonymous_not_allowed");
    await assertNotBlockedForPlay(ctx, me._id);
    if (args.clientBidId.length < 8 || args.clientBidId.length > 100) fail("invalid_request");
    const giftId = ctx.db.normalizeId("gifts", args.giftId);
    const gift = giftId ? await ctx.db.get("gifts", giftId) : null;
    if (!gift) fail("gift_not_found");
    const now = Date.now();

    const existing = await bidOf(ctx, gift._id, me._id);
    if (
      existing?.lastClientBidId === args.clientBidId &&
      existing.status === "leading" &&
      existing.amount === args.amount
    ) {
      return { status: "leading", amount: existing.amount, points: me.points };
    }

    const bid = evaluateGiftBid(gift, { uid: me._id, points: me.points }, args.amount, now);
    await movePoints(ctx, {
      uid: me._id,
      giftId: gift._id,
      type: bid.isRaise ? "raise" : "bid",
      delta: -bid.charge,
      now,
    });

    if (bid.refundUid) {
      const previous = await bidOf(ctx, gift._id, bid.refundUid);
      const refunded = await movePoints(ctx, {
        uid: bid.refundUid,
        giftId: gift._id,
        type: "refund_outbid",
        delta: bid.refundAmount,
        now,
      });
      if (previous) {
        await ctx.db.patch("giftBids", previous._id, {
          status: "outbid",
          updatedAt: now,
          ...(refunded ? {} : { refundSkipped: true }),
        });
      }
      if (refunded) await notifyOutbid(ctx, bid.refundUid, gift.name, previous?.language ?? "fr");
    }

    await ctx.db.patch("gifts", gift._id, {
      highestBid: args.amount,
      highestBidderUid: me._id,
      highestBidderNickname: me.nickname,
      highestBidAt: now,
      bidCount: gift.bidCount + 1,
      participantCount: gift.participantCount + (existing ? 0 : 1),
      updatedAt: now,
    });
    const shared = {
      nickname: me.nickname,
      amount: args.amount,
      status: "leading" as const,
      language: args.language,
      lastClientBidId: args.clientBidId,
      giftName: gift.name,
      giftImageUrl: gift.images[0]?.url,
      giftEndsAt: gift.endsAt,
      updatedAt: now,
      lastBidAt: now,
    };
    if (existing) {
      await ctx.db.patch("giftBids", existing._id, { ...shared, bidCount: existing.bidCount + 1 });
    } else {
      await ctx.db.insert("giftBids", {
        giftId: gift._id,
        uid: me._id,
        bidCount: 1,
        createdAt: now,
        ...shared,
      });
    }
    return { status: "leading", amount: args.amount, points: me.points - bid.charge };
  },
});

// ---------------------------------------------------------------------
// Scheduled work
// ---------------------------------------------------------------------

const CLOSE_BATCH = 50;

/** Cron: closes (or extends) auctions past their deadline. */
export const closeExpired = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = Date.now();
    const expired = await ctx.db
      .query("gifts")
      .withIndex("by_status_and_endsAt", (q) => q.eq("status", "open").lte("endsAt", now))
      .take(CLOSE_BATCH);
    for (const gift of expired) await resolveExpiredGift(ctx, gift, now);
    if (expired.length === CLOSE_BATCH) {
      await ctx.scheduler.runAfter(0, internal.gifts.closeExpired, {});
    }
    // Retry finalization that a failed continuation left behind.
    for (const status of ["closed", "cancelled"] as const) {
      const pending = await ctx.db
        .query("gifts")
        .withIndex("by_status_and_participantsFinalized", (q) =>
          q.eq("status", status).eq("participantsFinalized", false),
        )
        .take(10);
      for (const gift of pending) {
        await ctx.scheduler.runAfter(0, internal.gifts.finalizeParticipants, {
          giftId: gift._id,
          outcome: status === "closed" ? "lost" : "cancelled",
        });
      }
    }
    return null;
  },
});

const FINALIZE_BATCH = 200;

/** Settles the remaining outbid rows of a finished auction, in batches. */
export const finalizeParticipants = internalMutation({
  args: { giftId: v.id("gifts"), outcome: v.union(v.literal("lost"), v.literal("cancelled")) },
  handler: async (ctx, { giftId, outcome }) => {
    const gift = await ctx.db.get("gifts", giftId);
    if (!gift || gift.participantsFinalized !== false) return null;
    const now = Date.now();
    const rows = await ctx.db
      .query("giftBids")
      .withIndex("by_gift_and_status", (q) => q.eq("giftId", giftId).eq("status", "outbid"))
      .take(FINALIZE_BATCH);
    for (const row of rows) await ctx.db.patch("giftBids", row._id, { status: outcome, updatedAt: now });
    if (rows.length === FINALIZE_BATCH) {
      await ctx.scheduler.runAfter(0, internal.gifts.finalizeParticipants, { giftId, outcome });
    } else {
      await ctx.db.patch("gifts", giftId, { participantsFinalized: true });
    }
    return null;
  },
});
