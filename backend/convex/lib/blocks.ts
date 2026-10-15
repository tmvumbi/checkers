import type { Id } from "../_generated/dataModel";
import type { QueryCtx } from "../_generated/server";
import { fail } from "./errors";

export type EffectiveBlock = {
  level: "soft" | "full";
  permanent: boolean;
  expiresAt: number | null;
};

/**
 * Mirrors `_effective_block()`: the strongest of the player's active direct
 * blocks and any active flag on a device they have been seen on. For that
 * strongest level: permanent if any such block has no expiry, expiry = the
 * latest one.
 */
export async function effectiveBlock(
  ctx: QueryCtx,
  uid: Id<"profiles">,
  now: number,
): Promise<EffectiveBlock | null> {
  const found: { level: "soft" | "full"; expiresAt?: number }[] = [];
  const direct = await ctx.db
    .query("playerBlocks")
    .withIndex("by_uid", (q) => q.eq("uid", uid))
    .take(100);
  for (const b of direct) {
    if (b.revokedAt !== undefined) continue;
    if (b.expiresAt !== undefined && b.expiresAt <= now) continue;
    found.push({ level: b.level, expiresAt: b.expiresAt });
  }
  const devices = await ctx.db
    .query("playerDevices")
    .withIndex("by_uid_and_kind_and_value", (q) => q.eq("uid", uid))
    .take(50);
  for (const d of devices) {
    const flags = await ctx.db
      .query("blockedDevices")
      .withIndex("by_kind_and_value", (q) => q.eq("kind", d.kind).eq("value", d.value))
      .take(20);
    for (const f of flags) {
      if (f.expiresAt !== undefined && f.expiresAt <= now) continue;
      found.push({ level: f.level, expiresAt: f.expiresAt });
    }
  }
  if (found.length === 0) return null;
  const level = found.some((b) => b.level === "full") ? "full" : "soft";
  const strongest = found.filter((b) => b.level === level);
  const permanent = strongest.some((b) => b.expiresAt === undefined);
  const expiries = strongest.flatMap((b) => (b.expiresAt === undefined ? [] : [b.expiresAt]));
  return {
    level,
    permanent,
    expiresAt: expiries.length ? Math.max(...expiries) : null,
  };
}

/** Any block stops play (the old `enforce_play_block` trigger). */
export async function assertNotBlockedForPlay(ctx: QueryCtx, uid: Id<"profiles">) {
  if (await effectiveBlock(ctx, uid, Date.now())) fail("blocked");
}

/** Only a full block stops watching (the old `enforce_watch_block`). */
export async function assertCanWatch(ctx: QueryCtx, uid: Id<"profiles">) {
  const block = await effectiveBlock(ctx, uid, Date.now());
  if (block?.level === "full") fail("blocked");
}
