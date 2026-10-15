import type { Doc } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import { fail } from "./errors";

export const DEFAULT_RATING = 1200;

/** The caller's profile, or null when signed out / not yet provisioned. */
export async function currentProfile(ctx: QueryCtx): Promise<Doc<"profiles"> | null> {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) return null;
  return await ctx.db
    .query("profiles")
    .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
    .unique();
}

/** Signed-in caller's profile; `not_authenticated` otherwise. */
export async function requireProfile(ctx: QueryCtx): Promise<Doc<"profiles">> {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) fail("not_authenticated");
  const profile = await ctx.db
    .query("profiles")
    .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
    .unique();
  if (!profile) fail("profile_required");
  return profile;
}

/** Caller's profile with a nickname (every play path requires one). */
export async function requirePlayer(ctx: QueryCtx): Promise<Doc<"profiles">> {
  const profile = await requireProfile(ctx);
  if (profile.nickname === "") fail("profile_required");
  return profile;
}

export function isAnonymousIdentity(identity: Record<string, unknown>): boolean | undefined {
  const firebase = identity["firebase"] as { sign_in_provider?: unknown } | undefined;
  const provider = firebase?.sign_in_provider;
  return typeof provider === "string" ? provider === "anonymous" : undefined;
}

/** Creates the caller's profile on first sign-in (empty nickname). */
export async function getOrCreateProfile(
  ctx: MutationCtx,
  isAnonymousHint?: boolean,
): Promise<Doc<"profiles">> {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) fail("not_authenticated");
  const existing = await ctx.db
    .query("profiles")
    .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
    .unique();
  if (existing) return existing;
  const now = Date.now();
  const id = await ctx.db.insert("profiles", {
    tokenIdentifier: identity.tokenIdentifier,
    nickname: "",
    isAnonymous: isAnonymousIdentity(identity) ?? isAnonymousHint ?? true,
    rating: DEFAULT_RATING,
    ratedGames: 0,
    wins: 0,
    losses: 0,
    draws: 0,
    points: 0,
    createdAt: now,
    updatedAt: now,
  });
  return (await ctx.db.get("profiles", id))!;
}
