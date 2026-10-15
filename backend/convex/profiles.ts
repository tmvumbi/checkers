import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { currentProfile, getOrCreateProfile } from "./lib/auth";
import { fail } from "./lib/errors";
import { profileRow } from "./lib/serialize";

// Player profiles (0001). The profile id is the player's uid everywhere.

/** Provisions the caller's profile on sign-in and returns it. */
export const ensure = mutation({
  args: { isAnonymous: v.optional(v.boolean()) },
  handler: async (ctx, { isAnonymous }) => {
    const profile = await getOrCreateProfile(ctx, isAnonymous);
    if (isAnonymous !== undefined && profile.isAnonymous !== isAnonymous) {
      await ctx.db.patch("profiles", profile._id, { isAnonymous, updatedAt: Date.now() });
    }
    return profileRow((await ctx.db.get("profiles", profile._id))!);
  },
});

/** The caller's profile row, or null before provisioning. */
export const me = query({
  args: {},
  handler: async (ctx) => {
    const profile = await currentProfile(ctx);
    return profile ? profileRow(profile) : null;
  },
});

/** Any player's public profile row (profiles are world-readable). */
export const get = query({
  args: { uid: v.string() },
  handler: async (ctx, { uid }) => {
    const id = ctx.db.normalizeId("profiles", uid);
    const profile = id ? await ctx.db.get("profiles", id) : null;
    return profile ? profileRow(profile) : null;
  },
});

/** Client-editable identity columns only; stats stay server-owned. */
export const updateMine = mutation({
  args: {
    nickname: v.string(),
    photoUrl: v.optional(v.union(v.string(), v.null())),
    isAnonymous: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const profile = await getOrCreateProfile(ctx, args.isAnonymous);
    const nickname = args.nickname.trim();
    if ([...nickname].length > 20) fail("nickname_too_long");
    await ctx.db.patch("profiles", profile._id, {
      nickname,
      ...(args.photoUrl !== undefined ? { photoUrl: args.photoUrl ?? undefined } : {}),
      ...(args.photoUrl === null ? { photoStorageId: undefined } : {}),
      ...(args.isAnonymous !== undefined ? { isAnonymous: args.isAnonymous } : {}),
      updatedAt: Date.now(),
    });
    return profileRow((await ctx.db.get("profiles", profile._id))!);
  },
});
