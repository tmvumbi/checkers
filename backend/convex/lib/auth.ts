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

// Firebase `firebase.identities` provider keys → Supabase auth.identities
// provider names recorded on imported profiles.
const PROVIDERS: Record<string, string> = { "google.com": "google", "apple.com": "apple" };

/** Provider identities in a Firebase ID token, as (provider, subject). */
export function federatedIdentities(identity: Record<string, unknown>) {
  const firebase = identity["firebase"] as { identities?: Record<string, unknown> } | undefined;
  const out: { provider: string; subject: string }[] = [];
  for (const [key, subjects] of Object.entries(firebase?.identities ?? {})) {
    const provider = PROVIDERS[key];
    if (!provider || !Array.isArray(subjects)) continue;
    for (const subject of subjects) {
      if (typeof subject === "string") out.push({ provider, subject });
    }
  }
  return out;
}

/** An imported, still-unclaimed profile whose Google/Apple identity
 * matches the caller's token. */
async function unclaimedLegacyMatch(ctx: MutationCtx, identity: Record<string, unknown>) {
  for (const { provider, subject } of federatedIdentities(identity)) {
    const link = await ctx.db
      .query("legacyIdentities")
      .withIndex("by_provider_and_subject", (q) => q.eq("provider", provider).eq("subject", subject))
      .first();
    if (!link) continue;
    const profile = await ctx.db.get("profiles", link.profileId);
    if (profile && !profile.tokenIdentifier) return profile;
  }
  return null;
}

/** Creates the caller's profile on first sign-in (empty nickname), or
 * re-claims their imported Supabase profile by Google/Apple identity. */
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
  const legacy = await unclaimedLegacyMatch(ctx, identity);
  if (legacy) {
    await ctx.db.patch("profiles", legacy._id, {
      tokenIdentifier: identity.tokenIdentifier,
      isAnonymous: false,
      updatedAt: now,
    });
    return (await ctx.db.get("profiles", legacy._id))!;
  }
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
