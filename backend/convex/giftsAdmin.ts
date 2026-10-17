import { ConvexError, v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import { internalMutation, internalQuery, type MutationCtx } from "./_generated/server";
import {
  cancelGift,
  editableGiftFields,
  type GiftImage,
  type GiftInput,
  validateGiftInput,
  youtubeVideoId,
} from "./lib/gifts";
import { iso } from "./lib/time";

// Gift store administration for the admin console (scripts/admin_worker.js,
// Gifts tab). Only the /admin/api HTTP actions call these.

function giftRow(g: Doc<"gifts">, customer: Doc<"adCustomers"> | null) {
  return {
    id: g._id,
    name: g.name,
    description: g.description,
    images: g.images.map((i) => ({
      url: i.url,
      storage_id: i.storageId ?? null,
      width: i.width,
      height: i.height,
    })),
    youtube_video_id: g.youtubeVideoId ?? null,
    customer_id: g.customerId ?? null,
    customer_name: customer?.name ?? null,
    minimum_bid: g.minimumBid,
    ends_at: iso(g.endsAt),
    active: g.active,
    status: g.status,
    highest_bid: g.highestBid ?? null,
    highest_bidder_uid: g.highestBidderUid ?? null,
    highest_bidder_nickname: g.highestBidderNickname ?? null,
    highest_bid_at: iso(g.highestBidAt),
    bid_count: g.bidCount,
    participant_count: g.participantCount,
    extension_count: g.extensionCount,
    winner_uid: g.winnerUid ?? null,
    winner_nickname: g.winnerNickname ?? null,
    winner_amount: g.winnerAmount ?? null,
    closed_at: iso(g.closedAt),
    cancelled_at: iso(g.cancelledAt),
    delivered_at: iso(g.deliveredAt),
    delivery_note: g.deliveryNote ?? null,
    created_at: iso(g.createdAt),
    updated_at: iso(g.updatedAt),
  };
}

async function rowFor(ctx: MutationCtx, id: Id<"gifts">) {
  const gift = (await ctx.db.get("gifts", id))!;
  return giftRow(gift, gift.customerId ? await ctx.db.get("adCustomers", gift.customerId) : null);
}

function requireGiftId(ctx: MutationCtx, raw: string): Id<"gifts"> {
  const id = ctx.db.normalizeId("gifts", raw);
  if (!id) throw new ConvexError("unknown gift");
  return id;
}

const nullableString = v.optional(v.union(v.string(), v.null()));

/** Console payload (snake_case, as the page sends it). */
const giftInput = v.object({
  name: v.optional(v.string()),
  description: v.optional(v.string()),
  images: v.optional(
    v.array(
      v.object({
        url: v.string(),
        storage_id: nullableString,
        width: v.number(),
        height: v.number(),
      }),
    ),
  ),
  youtube_url: nullableString,
  customer_id: nullableString,
  minimum_bid: v.optional(v.number()),
  ends_at: v.optional(v.string()),
  active: v.optional(v.boolean()),
});
type RawGiftInput = typeof giftInput.type;

function toGiftInput(ctx: MutationCtx, raw: RawGiftInput): GiftInput {
  const input: GiftInput = {};
  if (raw.name !== undefined) input.name = raw.name;
  if (raw.description !== undefined) input.description = raw.description;
  if (raw.images !== undefined) {
    input.images = raw.images.map(
      (i): GiftImage => ({
        url: i.url,
        storageId: (i.storage_id && ctx.db.system.normalizeId("_storage", i.storage_id)) || undefined,
        width: i.width,
        height: i.height,
      }),
    );
  }
  if (raw.youtube_url !== undefined) input.youtubeVideoId = raw.youtube_url ? youtubeVideoId(raw.youtube_url) : null;
  if (raw.customer_id !== undefined) {
    if (raw.customer_id) {
      const id = ctx.db.normalizeId("adCustomers", raw.customer_id);
      if (!id) throw new ConvexError("unknown customer");
      input.customerId = id;
    } else {
      input.customerId = null;
    }
  }
  if (raw.minimum_bid !== undefined) input.minimumBid = raw.minimum_bid;
  if (raw.ends_at !== undefined) {
    const ms = Date.parse(raw.ends_at);
    if (Number.isNaN(ms)) throw new ConvexError("end date is invalid");
    input.endsAt = ms;
  }
  if (raw.active !== undefined) input.active = raw.active;
  return input;
}

/** Stored files no longer referenced after an image list change. */
async function deleteImages(ctx: MutationCtx, images: GiftImage[], keep: GiftImage[] = []) {
  const kept = new Set(keep.map((i) => i.storageId).filter(Boolean));
  for (const image of images) {
    if (image.storageId && !kept.has(image.storageId)) {
      try {
        await ctx.storage.delete(image.storageId);
      } catch {
        // Already gone; nothing to clean up.
      }
    }
  }
}

export const list = internalQuery({
  args: {},
  handler: async (ctx) => {
    const gifts = await ctx.db.query("gifts").order("desc").take(300);
    return await Promise.all(
      gifts.map(async (g) => giftRow(g, g.customerId ? await ctx.db.get("adCustomers", g.customerId) : null)),
    );
  },
});

export const create = internalMutation({
  args: { gift: giftInput },
  handler: async (ctx, args) => {
    const now = Date.now();
    const input = toGiftInput(ctx, args.gift);
    validateGiftInput(input, now, true);
    const id = await ctx.db.insert("gifts", {
      name: input.name!,
      description: input.description ?? "",
      images: input.images ?? [],
      youtubeVideoId: input.youtubeVideoId ?? undefined,
      customerId: input.customerId ?? undefined,
      minimumBid: input.minimumBid!,
      endsAt: input.endsAt!,
      active: input.active ?? true,
      status: "open",
      bidCount: 0,
      participantCount: 0,
      extensionCount: 0,
      createdAt: now,
      updatedAt: now,
    });
    return await rowFor(ctx, id);
  },
});

export const update = internalMutation({
  args: { id: v.string(), gift: giftInput },
  handler: async (ctx, args) => {
    const id = requireGiftId(ctx, args.id);
    const gift = (await ctx.db.get("gifts", id))!;
    const now = Date.now();
    const input = toGiftInput(ctx, args.gift);
    // An unchanged deadline may already be in the past (ending soon).
    if (input.endsAt === gift.endsAt) delete input.endsAt;
    if (input.minimumBid === gift.minimumBid) delete input.minimumBid;
    const editable = editableGiftFields(gift.status);
    for (const key of Object.keys(input)) {
      if (!editable.has(key)) throw new ConvexError(`${key} cannot change once the auction has ended`);
    }
    validateGiftInput(input, now, false);
    const patch: Partial<Doc<"gifts">> = { updatedAt: now };
    if (input.name !== undefined) patch.name = input.name;
    if (input.description !== undefined) patch.description = input.description;
    if (input.images !== undefined) patch.images = input.images;
    if (input.youtubeVideoId !== undefined) patch.youtubeVideoId = input.youtubeVideoId ?? undefined;
    if (input.customerId !== undefined) patch.customerId = input.customerId ?? undefined;
    if (input.minimumBid !== undefined) patch.minimumBid = input.minimumBid;
    if (input.endsAt !== undefined) patch.endsAt = input.endsAt;
    if (input.active !== undefined) patch.active = input.active;
    await ctx.db.patch("gifts", id, patch);
    if (input.images !== undefined) await deleteImages(ctx, gift.images, input.images);

    // Keep the copies on bid rows ("My gifts") in step.
    if (patch.name !== undefined || patch.images !== undefined || patch.endsAt !== undefined) {
      const updated = (await ctx.db.get("gifts", id))!;
      for await (const bid of ctx.db.query("giftBids").withIndex("by_gift_and_uid", (q) => q.eq("giftId", id))) {
        await ctx.db.patch("giftBids", bid._id, {
          giftName: updated.name,
          giftImageUrl: updated.images[0]?.url,
          giftEndsAt: updated.endsAt,
        });
      }
    }
    return await rowFor(ctx, id);
  },
});

export const cancel = internalMutation({
  args: { id: v.string() },
  handler: async (ctx, args) => {
    const id = requireGiftId(ctx, args.id);
    await cancelGift(ctx, (await ctx.db.get("gifts", id))!, Date.now());
    return await rowFor(ctx, id);
  },
});

export const remove = internalMutation({
  args: { id: v.string() },
  handler: async (ctx, args) => {
    const id = requireGiftId(ctx, args.id);
    const gift = (await ctx.db.get("gifts", id))!;
    if (gift.participantCount > 0 || gift.highestBidderUid) {
      throw new ConvexError("a gift with bids cannot be deleted — cancel it instead");
    }
    await deleteImages(ctx, gift.images);
    await ctx.db.delete("gifts", id);
    return { deleted: true };
  },
});

export const markDelivered = internalMutation({
  args: { id: v.string(), delivered: v.boolean(), note: nullableString },
  handler: async (ctx, args) => {
    const id = requireGiftId(ctx, args.id);
    const gift = (await ctx.db.get("gifts", id))!;
    if (gift.status !== "closed") throw new ConvexError("only won gifts can be marked delivered");
    const note = args.note?.trim();
    await ctx.db.patch("gifts", id, {
      deliveredAt: args.delivered ? Date.now() : undefined,
      deliveryNote: note ? note.slice(0, 500) : undefined,
      updatedAt: Date.now(),
    });
    return await rowFor(ctx, id);
  },
});

/** Bids and the points ledger of one gift. */
export const bids = internalQuery({
  args: { id: v.string() },
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("gifts", args.id);
    if (!id) return { bids: [], events: [] };
    const bids = await ctx.db
      .query("giftBids")
      .withIndex("by_gift_and_updatedAt", (q) => q.eq("giftId", id))
      .order("desc")
      .take(200);
    const events = await ctx.db
      .query("giftBidEvents")
      .withIndex("by_gift_and_at", (q) => q.eq("giftId", id))
      .order("desc")
      .take(100);
    const nicknames = new Map(bids.map((b) => [b.uid as string, b.nickname]));
    return {
      bids: bids.map((b) => ({
        uid: b.uid,
        nickname: b.nickname,
        amount: b.amount,
        status: b.status,
        refund_skipped: b.refundSkipped ?? false,
        bid_count: b.bidCount,
        language: b.language,
        last_bid_at: iso(b.lastBidAt),
      })),
      events: events.map((e) => ({
        at: iso(e.at),
        type: e.type,
        uid: e.uid,
        nickname: nicknames.get(e.uid) ?? null,
        amount: e.amount,
        points_before: e.pointsBefore,
        points_after: e.pointsAfter,
      })),
    };
  },
});
