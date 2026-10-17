import { ConvexError } from "convex/values";
import { internal } from "../_generated/api";
import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import { fail } from "./errors";
import { DAY, iso } from "./time";

// Gift store rules (port of kopo's functions/src/gift_store.ts). Players
// bid points on a gift; the highest bid when the countdown ends wins. Bids
// hold the points: an outbid leader is refunded in full, a leader raising
// their own bid pays only the difference. A gift nobody bid on moves its
// deadline forward a day at a time instead of closing without a winner.

export const GIFT_EXTENSION_MS = DAY;
export const MAX_GIFT_IMAGES = 10;
export const MAX_GIFT_BID = 1_000_000;
export const MAX_GIFT_NAME_LENGTH = 120;
export const MAX_GIFT_DESCRIPTION_LENGTH = 4000;
export const SITE_URL = "https://dame.cd";
export const CONTACT_EMAIL = "tresormvumbi@gmail.com";

export type GiftStatus = Doc<"gifts">["status"];
export type GiftLanguage = "en" | "fr";
export type GiftImage = Doc<"gifts">["images"][number];

/** Admin-facing validation error (the HTTP layer returns its text). */
function invalid(message: string): never {
  throw new ConvexError(message);
}

// ---------------------------------------------------------------------
// Pure rules
// ---------------------------------------------------------------------

/** Smallest bid the gift accepts right now. */
export function requiredBid(gift: Pick<Doc<"gifts">, "minimumBid" | "highestBid">): number {
  return Math.max(1, gift.minimumBid, (gift.highestBid ?? 0) + 1);
}

export type BidEvaluation = {
  /** Points taken from the bidder now. */
  charge: number;
  /** The bidder already leads and is raising their own bid. */
  isRaise: boolean;
  /** Previous leader to refund in full (never the bidder). */
  refundUid: Id<"profiles"> | null;
  refundAmount: number;
};

/** Checks a bid against the gift and the bidder's balance. */
export function evaluateGiftBid(
  gift: Doc<"gifts">,
  bidder: { uid: Id<"profiles">; points: number },
  amount: number,
  now: number,
): BidEvaluation {
  if (!gift.active || gift.status !== "open" || gift.endsAt <= now) fail("gift_closed");
  if (!Number.isInteger(amount) || amount < 1 || amount > MAX_GIFT_BID) fail("invalid_amount");
  if (amount < requiredBid(gift)) fail("bid_too_low");
  const isRaise = gift.highestBidderUid === bidder.uid;
  const charge = isRaise ? amount - (gift.highestBid ?? 0) : amount;
  if (charge > bidder.points) fail("not_enough_points");
  const refundUid = !isRaise && gift.highestBidderUid ? gift.highestBidderUid : null;
  return { charge, isRaise, refundUid, refundAmount: refundUid ? (gift.highestBid ?? 0) : 0 };
}

/** First deadline step (+24h, repeated) that lies after [now]. */
export function nextGiftEndsAt(endsAt: number, now: number): { endsAt: number; steps: number } {
  let next = endsAt;
  let steps = 0;
  while (next <= now) {
    next += GIFT_EXTENSION_MS;
    steps++;
  }
  return { endsAt: next, steps };
}

/** Fields an admin may change for a gift in [status]. Price and deadline
 * are part of the auction contract and freeze once it ends. */
export function editableGiftFields(status: GiftStatus): ReadonlySet<string> {
  const always = ["name", "description", "images", "youtubeVideoId", "customerId", "active"];
  return new Set(status === "open" ? [...always, "minimumBid", "endsAt"] : always);
}

/** YouTube video id from a URL (watch, youtu.be, embed, shorts) or a bare id. */
export function youtubeVideoId(raw: string): string | null {
  const text = raw.trim();
  if (text === "") return null;
  const id = /^[A-Za-z0-9_-]{11}$/;
  if (id.test(text)) return text;
  let url: URL;
  try {
    url = new URL(text);
  } catch {
    return invalid("YouTube link is not a valid URL");
  }
  const host = url.hostname.replace(/^www\.|^m\./, "");
  let candidate: string | null = null;
  if (host === "youtu.be") candidate = url.pathname.slice(1).split("/")[0];
  else if (host === "youtube.com" || host === "youtube-nocookie.com") {
    candidate = url.searchParams.get("v");
    const m = url.pathname.match(/^\/(embed|shorts|live)\/([^/]+)/);
    if (!candidate && m) candidate = m[2];
  }
  if (!candidate || !id.test(candidate)) return invalid("YouTube link has no video id");
  return candidate;
}

export type GiftInput = {
  name?: string;
  description?: string;
  images?: GiftImage[];
  youtubeVideoId?: string | null;
  customerId?: Id<"adCustomers"> | null;
  minimumBid?: number;
  endsAt?: number;
  active?: boolean;
};

/** Validates admin input; throws a readable message on the first problem. */
export function validateGiftInput(input: GiftInput, now: number, creating: boolean) {
  if (input.name !== undefined) {
    const name = input.name.trim();
    if (name === "") invalid("name is required");
    if (name.length > MAX_GIFT_NAME_LENGTH) invalid(`name is longer than ${MAX_GIFT_NAME_LENGTH} characters`);
    input.name = name;
  } else if (creating) invalid("name is required");
  if (input.description !== undefined) {
    input.description = input.description.trim();
    if (input.description.length > MAX_GIFT_DESCRIPTION_LENGTH) {
      invalid(`description is longer than ${MAX_GIFT_DESCRIPTION_LENGTH} characters`);
    }
  }
  if (input.images !== undefined) {
    if (input.images.length > MAX_GIFT_IMAGES) invalid(`at most ${MAX_GIFT_IMAGES} images`);
    for (const img of input.images) {
      if (!/^https:\/\//.test(img.url)) invalid("image URLs must be https");
      if (!(img.width > 0 && img.height > 0)) invalid("image width and height are required");
    }
  }
  if (input.minimumBid !== undefined) {
    if (!Number.isInteger(input.minimumBid) || input.minimumBid < 1 || input.minimumBid > MAX_GIFT_BID) {
      invalid(`minimum bid must be a whole number from 1 to ${MAX_GIFT_BID}`);
    }
  } else if (creating) invalid("minimum bid is required");
  if (input.endsAt !== undefined) {
    if (!Number.isFinite(input.endsAt)) invalid("end date is invalid");
    if (input.endsAt <= now) invalid("end date must be in the future");
  } else if (creating) invalid("end date is required");
}

// ---------------------------------------------------------------------
// Points movements (the only place the store changes profiles.points)
// ---------------------------------------------------------------------

type EventType = Doc<"giftBidEvents">["type"];

/** Adds [delta] (negative = charge) to the player's points and records it
 * in the ledger. Returns false when the profile no longer exists. */
export async function movePoints(
  ctx: MutationCtx,
  args: { uid: Id<"profiles">; giftId: Id<"gifts">; type: EventType; delta: number; now: number },
): Promise<boolean> {
  const profile = await ctx.db.get("profiles", args.uid);
  if (!profile) return false;
  const pointsAfter = profile.points + args.delta;
  if (pointsAfter < 0) fail("not_enough_points");
  if (args.delta !== 0) await ctx.db.patch("profiles", args.uid, { points: pointsAfter });
  await ctx.db.insert("giftBidEvents", {
    giftId: args.giftId,
    uid: args.uid,
    type: args.type,
    amount: Math.abs(args.delta),
    pointsBefore: profile.points,
    pointsAfter,
    refunded: args.delta > 0,
    at: args.now,
  });
  return true;
}

export async function bidOf(ctx: QueryCtx, giftId: Id<"gifts">, uid: Id<"profiles">) {
  return await ctx.db
    .query("giftBids")
    .withIndex("by_gift_and_uid", (q) => q.eq("giftId", giftId).eq("uid", uid))
    .unique();
}

const NO_LEADER = {
  highestBid: undefined,
  highestBidderUid: undefined,
  highestBidderNickname: undefined,
  highestBidAt: undefined,
};

/**
 * Takes [uid] out of every open auction they lead (admin block or account
 * deletion). The gift falls back to having no leader; with [refundType]
 * the held points go back to the player.
 */
export async function withdrawLeadingBids(
  ctx: MutationCtx,
  uid: Id<"profiles">,
  refundType: "refund_block" | null,
) {
  const now = Date.now();
  const leading = await ctx.db
    .query("giftBids")
    .withIndex("by_uid_and_status_and_giftEndsAt", (q) => q.eq("uid", uid).eq("status", "leading"))
    .take(200);
  for (const bid of leading) {
    const gift = await ctx.db.get("gifts", bid.giftId);
    if (!gift || gift.status !== "open" || gift.highestBidderUid !== uid) continue;
    if (refundType) {
      await movePoints(ctx, { uid, giftId: gift._id, type: refundType, delta: gift.highestBid ?? 0, now });
    }
    await ctx.db.patch("giftBids", bid._id, { status: "cancelled", updatedAt: now });
    await ctx.db.patch("gifts", gift._id, { ...NO_LEADER, updatedAt: now });
  }
  return leading.length;
}

// ---------------------------------------------------------------------
// Auction end
// ---------------------------------------------------------------------

/** Closes or extends one expired open gift. */
export async function resolveExpiredGift(ctx: MutationCtx, gift: Doc<"gifts">, now: number) {
  if (gift.status !== "open" || gift.endsAt > now) return;
  if (!gift.highestBidderUid) {
    const next = nextGiftEndsAt(gift.endsAt, now);
    await ctx.db.patch("gifts", gift._id, {
      endsAt: next.endsAt,
      extensionCount: gift.extensionCount + next.steps,
      updatedAt: now,
    });
    return;
  }
  const winnerUid = gift.highestBidderUid;
  const amount = gift.highestBid ?? 0;
  await ctx.db.patch("gifts", gift._id, {
    status: "closed",
    winnerUid,
    winnerNickname: gift.highestBidderNickname,
    winnerAmount: amount,
    closedAt: now,
    participantsFinalized: false,
    updatedAt: now,
  });
  const bid = await bidOf(ctx, gift._id, winnerUid);
  if (bid) await ctx.db.patch("giftBids", bid._id, { status: "won", updatedAt: now });
  const winner = await ctx.db.get("profiles", winnerUid);
  if (winner) {
    // Points were already taken when the bid was placed; this logs the win.
    await movePoints(ctx, { uid: winnerUid, giftId: gift._id, type: "win", delta: 0, now });
    await notifyWinner(ctx, gift, winnerUid, amount, bid?.language ?? "fr");
  }
  await ctx.scheduler.runAfter(0, internal.gifts.finalizeParticipants, { giftId: gift._id, outcome: "lost" });
}

/** Leading-bid refund when an admin cancels an open auction. */
export async function cancelGift(ctx: MutationCtx, gift: Doc<"gifts">, now: number) {
  if (gift.status !== "open") invalid("only open auctions can be cancelled");
  if (gift.highestBidderUid) {
    await movePoints(ctx, {
      uid: gift.highestBidderUid,
      giftId: gift._id,
      type: "refund_cancel",
      delta: gift.highestBid ?? 0,
      now,
    });
    const bid = await bidOf(ctx, gift._id, gift.highestBidderUid);
    if (bid) await ctx.db.patch("giftBids", bid._id, { status: "cancelled", updatedAt: now });
  }
  await ctx.db.patch("gifts", gift._id, {
    status: "cancelled",
    cancelledAt: now,
    participantsFinalized: false,
    updatedAt: now,
  });
  await ctx.scheduler.runAfter(0, internal.gifts.finalizeParticipants, {
    giftId: gift._id,
    outcome: "cancelled",
  });
}

// ---------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------

/** Push to every enabled device of [uid] through the checkers-push relay.
 * `admin_broadcast` makes the app show it as a dialog in the foreground. */
export async function pushToPlayer(
  ctx: MutationCtx,
  uid: Id<"profiles">,
  message: { title: string; body: string },
) {
  const devices = await ctx.db
    .query("pushDevices")
    .withIndex("by_uid", (q) => q.eq("uid", uid))
    .take(20);
  const tokens = devices.filter((d) => d.disabledAt === undefined).map((d) => d.fcmToken);
  if (tokens.length === 0) return;
  await ctx.scheduler.runAfter(0, internal.push.relay, {
    tokens,
    title: message.title,
    body: message.body,
    data: { type: "admin_broadcast" },
  });
}

const OUTBID_TEXT = {
  en: (gift: string) => ({
    title: "You have been outbid",
    body: `Someone bid more on “${gift}”. Your points are back — bid again at dame.cd/gifts.`,
  }),
  fr: (gift: string) => ({
    title: "Votre mise a été dépassée",
    body: `Quelqu’un a misé plus sur « ${gift} ». Vos points vous sont rendus — misez à nouveau sur dame.cd/gifts.`,
  }),
};

export async function notifyOutbid(
  ctx: MutationCtx,
  uid: Id<"profiles">,
  giftName: string,
  language: GiftLanguage,
) {
  await pushToPlayer(ctx, uid, OUTBID_TEXT[language](giftName));
}

const WIN_TEXT = {
  en: (gift: string, amount: number) => ({
    title: "You won a gift!",
    body: `Congratulations! You won “${gift}” for ${amount} points.`,
    html:
      `<p><b>Congratulations!</b> You won <b>${escapeHtml(gift)}</b> in the gift store ` +
      `for ${amount} points.</p><p>We will contact you to arrange delivery. You can also ` +
      `write to us at ${CONTACT_EMAIL} or through “Write to Admins” in the app.</p>`,
  }),
  fr: (gift: string, amount: number) => ({
    title: "Vous avez gagné un cadeau !",
    body: `Félicitations ! Vous avez gagné « ${gift} » pour ${amount} points.`,
    html:
      `<p><b>Félicitations !</b> Vous avez gagné <b>${escapeHtml(gift)}</b> dans la boutique ` +
      `cadeaux pour ${amount} points.</p><p>Nous vous contacterons pour organiser la livraison. ` +
      `Vous pouvez aussi nous écrire à ${CONTACT_EMAIL} ou via « Écrire aux admins » dans l’application.</p>`,
  }),
};

function escapeHtml(text: string) {
  return text.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}

/** Private inbox message (both languages: the app shows the one matching
 * its locale) plus a push in the language the winner last bid in. */
async function notifyWinner(
  ctx: MutationCtx,
  gift: Doc<"gifts">,
  uid: Id<"profiles">,
  amount: number,
  language: GiftLanguage,
) {
  const now = Date.now();
  for (const lang of ["en", "fr"] as const) {
    await ctx.db.insert("playerMessages", {
      type: "private",
      language: lang,
      targetUid: uid,
      htmlText: WIN_TEXT[lang](gift.name, amount).html,
      imageUrl: gift.images[0]?.url,
      linkUrl: `${SITE_URL}/gifts/mine?lang=${lang}`,
      publishAt: now,
      expiresAt: now + 60 * DAY,
      enabled: true,
      createdAt: now,
      updatedAt: now,
    });
  }
  const text = WIN_TEXT[language](gift.name, amount);
  await pushToPlayer(ctx, uid, { title: text.title, body: text.body });
}

// ---------------------------------------------------------------------
// Row shapes (snake_case, ISO dates, explicit nulls — like the rest of the API)
// ---------------------------------------------------------------------

export function publicGiftRow(g: Doc<"gifts">, offeredBy: string | null) {
  return {
    id: g._id,
    name: g.name,
    description: g.description,
    images: g.images.map((i) => ({ url: i.url, width: i.width, height: i.height })),
    youtube_video_id: g.youtubeVideoId ?? null,
    offered_by: offeredBy,
    minimum_bid: g.minimumBid,
    required_bid: requiredBid(g),
    ends_at: iso(g.endsAt),
    status: g.status,
    highest_bid: g.highestBid ?? null,
    highest_bidder_nickname: g.highestBidderNickname ?? null,
    highest_bid_at: iso(g.highestBidAt),
    bid_count: g.bidCount,
    participant_count: g.participantCount,
    winner_nickname: g.winnerNickname ?? null,
    winner_amount: g.winnerAmount ?? null,
    closed_at: iso(g.closedAt),
  };
}

export function bidRow(b: Doc<"giftBids">) {
  return {
    id: b._id,
    gift_id: b.giftId,
    gift_name: b.giftName,
    gift_image_url: b.giftImageUrl ?? null,
    gift_ends_at: iso(b.giftEndsAt),
    amount: b.amount,
    status: b.status,
    bid_count: b.bidCount,
    last_bid_at: iso(b.lastBidAt),
    updated_at: iso(b.updatedAt),
  };
}
