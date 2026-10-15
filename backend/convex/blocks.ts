import { v } from "convex/values";
import type { Id } from "./_generated/dataModel";
import { internalMutation, mutation, type MutationCtx } from "./_generated/server";
import { requireProfile } from "./lib/auth";
import { effectiveBlock } from "./lib/blocks";
import { fail } from "./lib/errors";
import { DAY } from "./lib/time";

// Player blocking with device-level enforcement (0016).

const KINDS = new Set(["android_ssaid", "ios_keychain", "ios_idfv"]);
const FLEET_VALUES = new Set([
  "9774d56d682e549c",
  "unknown",
  "null",
  "00000000-0000-0000-0000-000000000000",
]);

/** `sync_device_blocks`: records this install's device ids and returns
 * the effective block `{level, permanent, expires_at}`. */
export const syncDeviceBlocks = mutation({
  args: { devices: v.array(v.object({ kind: v.string(), value: v.string() })) },
  handler: async (ctx, { devices }) => {
    const me = await requireProfile(ctx);
    const now = Date.now();
    for (const device of devices.slice(0, 10)) {
      const value = device.value.trim();
      if (!KINDS.has(device.kind)) continue;
      if (value.length < 8 || value.length > 128 || FLEET_VALUES.has(value.toLowerCase())) continue;
      const kind = device.kind as "android_ssaid" | "ios_keychain" | "ios_idfv";
      const existing = await ctx.db
        .query("playerDevices")
        .withIndex("by_uid_and_kind_and_value", (q) =>
          q.eq("uid", me._id).eq("kind", kind).eq("value", value),
        )
        .unique();
      if (existing) await ctx.db.patch("playerDevices", existing._id, { lastSeenAt: now });
      else {
        await ctx.db.insert("playerDevices", {
          uid: me._id,
          kind,
          value,
          firstSeenAt: now,
          lastSeenAt: now,
        });
      }
    }
    const block = await effectiveBlock(ctx, me._id, now);
    if (!block) return { level: null };
    return {
      level: block.level,
      permanent: block.permanent,
      expires_at:
        block.permanent || block.expiresAt === null ? null : new Date(block.expiresAt).toISOString(),
    };
  },
});

async function revokeActive(ctx: MutationCtx, uid: Id<"profiles">, now: number) {
  let revoked = 0;
  const blocks = await ctx.db
    .query("playerBlocks")
    .withIndex("by_uid", (q) => q.eq("uid", uid))
    .take(100);
  for (const b of blocks) {
    if (b.revokedAt !== undefined) continue;
    await ctx.db.patch("playerBlocks", b._id, { revokedAt: now });
    const flags = await ctx.db
      .query("blockedDevices")
      .withIndex("by_block", (q) => q.eq("blockId", b._id))
      .take(100);
    for (const flag of flags) await ctx.db.delete("blockedDevices", flag._id);
    revoked++;
  }
  return revoked;
}

/** `block_player` (admin): replaces the player's block and flags every
 * device they have been seen on. `days` omitted = permanent. */
export const blockPlayer = internalMutation({
  args: {
    uid: v.id("profiles"),
    level: v.string(),
    days: v.optional(v.union(v.number(), v.null())),
    reason: v.optional(v.union(v.string(), v.null())),
  },
  handler: async (ctx, args) => {
    if (args.level !== "soft" && args.level !== "full") fail("level must be soft or full");
    const level = args.level;
    const now = Date.now();
    const expiresAt = args.days == null ? undefined : now + args.days * DAY;
    await revokeActive(ctx, args.uid, now);
    const blockId = await ctx.db.insert("playerBlocks", {
      uid: args.uid,
      level,
      reason: args.reason ?? undefined,
      expiresAt,
      createdAt: now,
    });
    const devices = await ctx.db
      .query("playerDevices")
      .withIndex("by_uid_and_kind_and_value", (q) => q.eq("uid", args.uid))
      .take(50);
    for (const d of devices) {
      await ctx.db.insert("blockedDevices", { blockId, kind: d.kind, value: d.value, level, expiresAt });
    }
    return {
      block_id: blockId,
      level,
      expires_at: expiresAt === undefined ? null : new Date(expiresAt).toISOString(),
      devices_flagged: devices.length,
    };
  },
});

/** `unblock_player` (admin). */
export const unblockPlayer = internalMutation({
  args: { uid: v.id("profiles") },
  handler: async (ctx, { uid }) => ({ blocks_revoked: await revokeActive(ctx, uid, Date.now()) }),
});
