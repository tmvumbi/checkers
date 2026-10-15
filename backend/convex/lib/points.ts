import type { Id } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";

/**
 * Mirrors `_record_point_award()`: an idempotent ledger entry plus the
 * profile credit. The (awardType, sourceId, uid) key means retries never
 * credit the same result twice. Returns whether points were granted.
 */
export async function recordPointAward(
  ctx: MutationCtx,
  args: {
    uid: Id<"profiles"> | undefined;
    awardType: "pc_win" | "tournament_win";
    sourceId: string;
    points: number;
    metadata?: Record<string, unknown>;
  },
): Promise<boolean> {
  const { uid, awardType, sourceId, points } = args;
  if (!uid || points <= 0) return false;
  const existing = await ctx.db
    .query("pointAwards")
    .withIndex("by_type_and_source_and_uid", (q) =>
      q.eq("awardType", awardType).eq("sourceId", sourceId).eq("uid", uid),
    )
    .unique();
  if (existing) return false;
  const profile = await ctx.db.get("profiles", uid);
  if (!profile) return false;
  await ctx.db.insert("pointAwards", {
    uid,
    awardType,
    sourceId,
    points,
    metadata: args.metadata ?? {},
    createdAt: Date.now(),
  });
  await ctx.db.patch("profiles", uid, { points: profile.points + points });
  return true;
}
