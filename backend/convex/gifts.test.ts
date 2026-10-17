import { afterEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import { DAY, HOUR } from "./lib/time";
import { newBackend, player, type Backend } from "./test.setup";

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

type Player = Awaited<ReturnType<typeof player>>;

async function withPoints(t: Backend, name: string, points: number) {
  const p = await player(t, name);
  await t.run(async (ctx) => {
    await ctx.db.patch("profiles", p.uid as Id<"profiles">, { points, isAnonymous: false });
    await ctx.db.insert("pushDevices", {
      uid: p.uid as Id<"profiles">,
      fcmToken: `token-${name}-0123456789`,
      platform: "android",
      createdAt: Date.now(),
      lastSeenAt: Date.now(),
    });
  });
  return p;
}

async function points(t: Backend, p: Player) {
  return await t.run(async (ctx) => (await ctx.db.get("profiles", p.uid as Id<"profiles">))!.points);
}

async function newGift(t: Backend, extra: { minimum_bid?: number; ends_at?: string } = {}) {
  const row = await t.mutation(internal.giftsAdmin.create, {
    gift: {
      name: "Smart watch",
      description: "A watch",
      minimum_bid: extra.minimum_bid ?? 10,
      ends_at: extra.ends_at ?? new Date(Date.now() + 2 * DAY).toISOString(),
      images: [],
    },
  });
  return row.id as string;
}

let bidSeq = 0;
function bid(p: Player, giftId: string, amount: number, clientBidId = `bid-${++bidSeq}-xxxxxxxx`) {
  return p.as.mutation(api.gifts.placeBid, { giftId, amount, clientBidId, language: "en" });
}

/** Every player's ledger must add up to their balance change. */
async function ledgerNet(t: Backend, p: Player) {
  return await t.run(async (ctx) => {
    const events = await ctx.db
      .query("giftBidEvents")
      .withIndex("by_uid", (q) => q.eq("uid", p.uid as Id<"profiles">))
      .take(100);
    return events.reduce((sum, e) => sum + (e.pointsAfter - e.pointsBefore), 0);
  });
}

async function scheduledRelays(t: Backend) {
  return await t.run(async (ctx) =>
    (await ctx.db.system.query("_scheduled_functions").take(100)).filter((f) => f.name.startsWith("push")),
  );
}

describe("bidding", () => {
  test("minimum, leader+1, outbid refund and raise by difference", async () => {
    const t = newBackend();
    const alice = await withPoints(t, "alice", 100);
    const bob = await withPoints(t, "bob", 100);
    const giftId = await newGift(t);

    await expect(bid(alice, giftId, 9)).rejects.toMatchObject({ data: "bid_too_low" });
    await bid(alice, giftId, 10);
    expect(await points(t, alice)).toBe(90);

    await expect(bid(bob, giftId, 10)).rejects.toMatchObject({ data: "bid_too_low" });
    await bid(bob, giftId, 15);
    expect([await points(t, alice), await points(t, bob)]).toEqual([100, 85]);

    // Bob raises his own lead: only the difference is charged.
    await bid(bob, giftId, 20);
    expect(await points(t, bob)).toBe(80);

    const gift = await alice.as.query(api.gifts.get, { id: giftId });
    expect(gift).toMatchObject({
      highest_bid: 20,
      highest_bidder_nickname: "bob",
      required_bid: 21,
      bid_count: 3,
      participant_count: 2,
      leader_is_me: false,
      my_bid: { status: "outbid", amount: 10 },
    });
    expect(await ledgerNet(t, alice)).toBe(0);
    expect(await ledgerNet(t, bob)).toBe(-20);
    // Alice was told she was outbid.
    expect((await scheduledRelays(t)).length).toBe(1);
  });

  test("not enough points, invalid amounts, closed gifts", async () => {
    const t = newBackend();
    const alice = await withPoints(t, "alice", 12);
    const giftId = await newGift(t);
    await expect(bid(alice, giftId, 13)).rejects.toMatchObject({ data: "not_enough_points" });
    await expect(bid(alice, giftId, 10.5)).rejects.toMatchObject({ data: "invalid_amount" });
    await t.mutation(internal.giftsAdmin.update, { id: giftId, gift: { active: false } });
    await expect(bid(alice, giftId, 10)).rejects.toMatchObject({ data: "gift_closed" });
    expect(await alice.as.query(api.gifts.listOpen, {})).toEqual([]);
  });

  test("guests and blocked players cannot bid", async () => {
    const t = newBackend();
    const guest = await withPoints(t, "guest", 50);
    const blocked = await withPoints(t, "blocked", 50);
    const giftId = await newGift(t);
    await t.run(async (ctx) => ctx.db.patch("profiles", guest.uid as Id<"profiles">, { isAnonymous: true }));
    await expect(bid(guest, giftId, 10)).rejects.toMatchObject({ data: "anonymous_not_allowed" });
    await t.mutation(internal.blocks.blockPlayer, { uid: blocked.uid as Id<"profiles">, level: "soft" });
    await expect(bid(blocked, giftId, 10)).rejects.toMatchObject({ data: "blocked" });
  });

  test("a retried bid is not charged twice", async () => {
    const t = newBackend();
    const alice = await withPoints(t, "alice", 50);
    const giftId = await newGift(t);
    await bid(alice, giftId, 10, "same-request-id");
    await bid(alice, giftId, 10, "same-request-id");
    expect(await points(t, alice)).toBe(40);
    const gift = await alice.as.query(api.gifts.get, { id: giftId });
    expect([gift?.bid_count, gift?.leader_is_me]).toEqual([1, true]);
  });
});

describe("auction end", () => {
  test("no bids: the deadline moves a day at a time", async () => {
    const t = newBackend();
    const giftId = await newGift(t);
    const endsAt = Date.now() - 3 * HOUR;
    await t.run(async (ctx) => ctx.db.patch("gifts", giftId as Id<"gifts">, { endsAt }));
    await t.mutation(internal.gifts.closeExpired, {});
    const gift = await t.run(async (ctx) => ctx.db.get("gifts", giftId as Id<"gifts">));
    expect([gift?.status, gift?.endsAt, gift?.extensionCount]).toEqual(["open", endsAt + DAY, 1]);
  });

  test("the leader wins, losers are settled, the winner is notified", async () => {
    vi.useFakeTimers();
    const t = newBackend();
    const alice = await withPoints(t, "alice", 100);
    const bob = await withPoints(t, "bob", 100);
    const giftId = await newGift(t);
    await bid(alice, giftId, 10);
    await bid(bob, giftId, 30);
    await t.run(async (ctx) => ctx.db.patch("gifts", giftId as Id<"gifts">, { endsAt: Date.now() - 1 }));
    await t.mutation(internal.gifts.closeExpired, {});
    await t.finishAllScheduledFunctions(vi.runAllTimers);

    const winners = await alice.as.query(api.gifts.winners, { paginationOpts: { numItems: 10, cursor: null } });
    expect(winners.page.map((g) => [g.winner_nickname, g.winner_amount, g.status])).toEqual([["bob", 30, "closed"]]);
    const wins = await bob.as.query(api.gifts.myWins, { paginationOpts: { numItems: 10, cursor: null } });
    expect(wins.page.map((b) => b.status)).toEqual(["won"]);
    expect(await alice.as.query(api.gifts.myBids, {})).toEqual([]);
    const aliceRow = await alice.as.query(api.gifts.get, { id: giftId });
    expect(aliceRow?.my_bid?.status).toBe("lost");
    const gift = await t.run(async (ctx) => ctx.db.get("gifts", giftId as Id<"gifts">));
    expect(gift?.participantsFinalized).toBe(true);
    // Points stay spent; both inbox languages got the message.
    expect([await points(t, alice), await points(t, bob)]).toEqual([100, 70]);
    const inbox = await bob.as.query(api.messages.mine, {});
    expect(inbox.map((m) => m.language).sort()).toEqual(["en", "fr"]);
    expect(inbox[0].html_text).toContain("Smart watch");
  });
});

describe("admin", () => {
  test("cancel refunds the leader; a gift with bids cannot be deleted", async () => {
    vi.useFakeTimers();
    const t = newBackend();
    const alice = await withPoints(t, "alice", 100);
    const bob = await withPoints(t, "bob", 100);
    const giftId = await newGift(t);
    await bid(alice, giftId, 10);
    await bid(bob, giftId, 25);
    await expect(t.mutation(internal.giftsAdmin.remove, { id: giftId })).rejects.toThrow(/cannot be deleted/);
    await t.mutation(internal.giftsAdmin.cancel, { id: giftId });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    expect([await points(t, alice), await points(t, bob)]).toEqual([100, 100]);
    expect((await alice.as.query(api.gifts.get, { id: giftId }))?.my_bid?.status).toBe("cancelled");
    expect((await bob.as.query(api.gifts.get, { id: giftId }))?.my_bid?.status).toBe("cancelled");
    await expect(t.mutation(internal.giftsAdmin.cancel, { id: giftId })).rejects.toThrow(/only open/);
  });

  test("price and deadline freeze once the auction ended; removed images are deleted", async () => {
    const t = newBackend();
    const storageId = await t.run(async (ctx) => ctx.storage.store(new Blob(["png"], { type: "image/png" })));
    const url = "https://example.convex.cloud/api/storage/x";
    const giftId = await newGift(t);
    await t.mutation(internal.giftsAdmin.update, {
      id: giftId,
      gift: { images: [{ url, storage_id: storageId, width: 10, height: 10 }] },
    });
    await t.mutation(internal.giftsAdmin.update, { id: giftId, gift: { images: [] } });
    expect(await t.run(async (ctx) => ctx.storage.getUrl(storageId))).toBeNull();

    await t.mutation(internal.giftsAdmin.cancel, { id: giftId });
    await expect(
      t.mutation(internal.giftsAdmin.update, { id: giftId, gift: { minimum_bid: 99 } }),
    ).rejects.toThrow(/minimumBid cannot change/);
    const row = await t.mutation(internal.giftsAdmin.update, { id: giftId, gift: { name: "Renamed" } });
    expect(row.name).toBe("Renamed");
  });

  test("blocking a leader refunds them; deleting an account clears its lead", async () => {
    const t = newBackend();
    const alice = await withPoints(t, "alice", 100);
    const bob = await withPoints(t, "bob", 100);
    const first = await newGift(t);
    const second = await newGift(t);
    await bid(alice, first, 40);
    await bid(bob, second, 20);
    await t.mutation(internal.blocks.blockPlayer, { uid: alice.uid as Id<"profiles">, level: "soft" });
    expect(await points(t, alice)).toBe(100);
    expect(await ledgerNet(t, alice)).toBe(0);
    await bob.as.mutation(api.account.deleteMine, {});
    for (const id of [first, second]) {
      const gift = await t.run(async (ctx) => ctx.db.get("gifts", id as Id<"gifts">));
      expect(gift?.highestBidderUid).toBeUndefined();
    }
  });

  test("HTTP API: auth, create, list, bids", async () => {
    vi.stubEnv("ADMIN_API_SECRET", "s3cret");
    const t = newBackend();
    const auth = { Authorization: "Bearer s3cret", "Content-Type": "application/json" };
    expect((await t.fetch("/admin/api/gifts")).status).toBe(401);
    const bad = await t.fetch("/admin/api/gifts", {
      method: "POST",
      headers: auth,
      body: JSON.stringify({ name: "x", minimum_bid: 5, ends_at: "2001-01-01T00:00:00Z" }),
    });
    expect([bad.status, (await bad.json()).error]).toEqual([400, "end date must be in the future"]);
    const created = await t.fetch("/admin/api/gifts", {
      method: "POST",
      headers: auth,
      body: JSON.stringify({
        name: "Phone",
        minimum_bid: "5",
        ends_at: new Date(Date.now() + DAY).toISOString(),
        youtube_url: "https://youtu.be/dQw4w9WgXcQ",
      }),
    });
    expect(created.status).toBe(201);
    const gift = await created.json();
    expect([gift.minimum_bid, gift.youtube_video_id, gift.status]).toEqual([5, "dQw4w9WgXcQ", "open"]);
    const alice = await withPoints(t, "alice", 10);
    await bid(alice, gift.id, 7);
    const bids = await (await t.fetch(`/admin/api/gift-bids/${gift.id}`, { headers: auth })).json();
    expect(bids.bids.map((b: any) => [b.nickname, b.amount])).toEqual([["alice", 7]]);
    expect(bids.events.map((e: any) => [e.type, e.points_before, e.points_after])).toEqual([["bid", 10, 3]]);
    const del = await t.fetch(`/admin/api/gifts/${gift.id}`, { method: "DELETE", headers: auth });
    expect(del.status).toBe(400);
    const list = await (await t.fetch("/admin/api/gifts", { headers: auth })).json();
    expect(list.map((g: any) => g.highest_bidder_nickname)).toEqual(["alice"]);
  });
});
