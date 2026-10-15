import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { action, env, internalMutation, mutation, type MutationCtx } from "./_generated/server";
import { isAnonymousIdentity, requireProfile } from "./lib/auth";
import { finishGame, other, seatsOf } from "./lib/games";

// Account lifecycle: deletion (0007/0037) and the Supabase → Convex
// account handoff.

const DELETED_NICKNAME = "Deleted player";

/** `delete_account`: resigns live games, anonymises the game record and
 * removes the player's personal rows. The Firebase user itself is deleted
 * by the client (FirebaseAuth currentUser.delete()). */
export const deleteMine = mutation({
  args: {},
  handler: async (ctx) => {
    const me = await requireProfile(ctx);
    await deleteProfile(ctx, me);
    return null;
  },
});

async function deleteProfile(ctx: MutationCtx, me: Doc<"profiles">) {
  const uid = me._id;

  const live = await ctx.db
    .query("gamePlayers")
    .withIndex("by_uid_and_status", (q) => q.eq("uid", uid).eq("gameStatus", "playing"))
    .take(50);
  for (const seat of live) {
    const color = seat.color ?? "white";
    await finishGame(
      ctx,
      seat.gameId,
      color === "white" ? "blackWin" : "whiteWin",
      "resignation",
      other(color),
    );
  }

  for await (const seat of ctx.db
    .query("gamePlayers")
    .withIndex("by_uid_and_status", (q) => q.eq("uid", uid))) {
    if (seat.gameStatus === "waiting") {
      await ctx.db.delete("gamePlayers", seat._id);
      if ((await seatsOf(ctx, seat.gameId)).length === 0) {
        const game = await ctx.db.get("games", seat.gameId);
        if (game) await ctx.db.delete("games", game._id);
      }
      continue;
    }
    await ctx.db.patch("gamePlayers", seat._id, { nickname: DELETED_NICKNAME, photoUrl: undefined });
    const game = await ctx.db.get("games", seat.gameId);
    if (game?.playerSearch) {
      const seats = await seatsOf(ctx, game._id);
      await ctx.db.patch("games", game._id, {
        playerSearch: seats.map((s) => s.nickname.toLowerCase()).join("\n"),
      });
    }
  }
  for await (const tp of ctx.db.query("tournamentPlayers").withIndex("by_uid", (q) => q.eq("uid", uid))) {
    await ctx.db.patch("tournamentPlayers", tp._id, { nickname: DELETED_NICKNAME, photoUrl: undefined });
  }

  const presence = await ctx.db.query("playerPresence").withIndex("by_uid", (q) => q.eq("uid", uid)).take(10);
  for (const r of presence) await ctx.db.delete("playerPresence", r._id);
  for await (const r of ctx.db.query("invites").withIndex("by_invitee", (q) => q.eq("inviteeUid", uid))) {
    await ctx.db.delete("invites", r._id);
  }
  for await (const r of ctx.db.query("invites").withIndex("by_inviter", (q) => q.eq("inviterUid", uid))) {
    await ctx.db.delete("invites", r._id);
  }
  for await (const r of ctx.db.query("gameWatchers").withIndex("by_uid", (q) => q.eq("uid", uid))) {
    await ctx.db.delete("gameWatchers", r._id);
  }
  for await (const r of ctx.db.query("tournamentLobby").withIndex("by_uid", (q) => q.eq("uid", uid))) {
    await ctx.db.delete("tournamentLobby", r._id);
  }
  for await (const r of ctx.db
    .query("tournamentInvites")
    .withIndex("by_invitee_and_created", (q) => q.eq("inviteeUid", uid))) {
    await ctx.db.delete("tournamentInvites", r._id);
  }
  for await (const r of ctx.db.query("tournamentNotifyOptins").withIndex("by_uid", (q) => q.eq("uid", uid))) {
    await ctx.db.delete("tournamentNotifyOptins", r._id);
  }
  for await (const r of ctx.db.query("pushDevices").withIndex("by_uid", (q) => q.eq("uid", uid))) {
    await ctx.db.delete("pushDevices", r._id);
  }
  for await (const r of ctx.db.query("playerMessages").withIndex("by_target", (q) => q.eq("targetUid", uid))) {
    await ctx.db.delete("playerMessages", r._id);
  }
  for await (const r of ctx.db.query("legacyIdentities").withIndex("by_profile", (q) => q.eq("profileId", uid))) {
    await ctx.db.delete("legacyIdentities", r._id);
  }
  if (me.photoStorageId) await ctx.storage.delete(me.photoStorageId);
  // Blocks and device records stay: they must keep binding the devices.
  await ctx.db.delete("profiles", uid);
}

// ---------------------------------------------------------------------
// Supabase → Convex account handoff
// ---------------------------------------------------------------------

type ClaimResult =
  | { status: "claimed"; uid: string }
  | { status: "already_claimed"; uid: string }
  | { status: "not_found" }
  | { status: "claimed_by_other" }
  | { status: "current_account_in_use" }
  | { status: "invalid_session" }
  | { status: "unavailable" };

/** Does this (fresh) profile have history worth protecting? */
async function hasActivity(ctx: MutationCtx, p: Doc<"profiles">) {
  if (p.ratedGames > 0 || p.points > 0) return true;
  const seat = await ctx.db
    .query("gamePlayers")
    .withIndex("by_uid_and_status", (q) => q.eq("uid", p._id))
    .first();
  return seat !== null;
}

/**
 * Points [legacy] (an imported Supabase profile) at the caller's Firebase
 * identity. The caller's fresh placeholder profile, if any, is folded in.
 */
export async function attachLegacyProfile(
  ctx: MutationCtx,
  legacy: Doc<"profiles">,
  identity: { tokenIdentifier: string; isAnonymous?: boolean },
): Promise<ClaimResult> {
  if (legacy.tokenIdentifier === identity.tokenIdentifier) {
    return { status: "already_claimed", uid: legacy._id };
  }
  if (legacy.tokenIdentifier) return { status: "claimed_by_other" };

  const current = await ctx.db
    .query("profiles")
    .withIndex("by_token", (q) => q.eq("tokenIdentifier", identity.tokenIdentifier))
    .unique();
  if (current) {
    if (await hasActivity(ctx, current)) return { status: "current_account_in_use" };
    for await (const d of ctx.db.query("pushDevices").withIndex("by_uid", (q) => q.eq("uid", current._id))) {
      await ctx.db.patch("pushDevices", d._id, { uid: legacy._id });
    }
    for await (const d of ctx.db
      .query("playerDevices")
      .withIndex("by_uid_and_kind_and_value", (q) => q.eq("uid", current._id))) {
      await ctx.db.patch("playerDevices", d._id, { uid: legacy._id });
    }
    await deleteProfile(ctx, current);
  }
  await ctx.db.patch("profiles", legacy._id, {
    tokenIdentifier: identity.tokenIdentifier,
    ...(identity.isAnonymous !== undefined ? { isAnonymous: identity.isAnonymous } : {}),
    updatedAt: Date.now(),
  });
  return { status: "claimed", uid: legacy._id };
}

export const attachLegacy = internalMutation({
  args: {
    legacyUid: v.string(),
    tokenIdentifier: v.string(),
    isAnonymous: v.optional(v.boolean()),
  },
  handler: async (ctx, args): Promise<ClaimResult> => {
    const legacy = await ctx.db
      .query("profiles")
      .withIndex("by_legacy_id", (q) => q.eq("legacyId", args.legacyUid))
      .unique();
    if (!legacy) return { status: "not_found" };
    return await attachLegacyProfile(ctx, legacy, args);
  },
});

/**
 * The app sends its still-stored Supabase access token after upgrading;
 * GoTrue confirms whose it is, and that player's imported profile moves
 * to the caller's Firebase identity. Works for guests too.
 */
export const claimLegacy = action({
  args: { supabaseAccessToken: v.string() },
  handler: async (ctx, { supabaseAccessToken }): Promise<ClaimResult> => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) return { status: "invalid_session" };
    const base = env.SUPABASE_LEGACY_URL;
    const anonKey = env.SUPABASE_LEGACY_ANON_KEY;
    if (!base || !anonKey) return { status: "unavailable" };
    let legacyUid: string | undefined;
    try {
      const res = await fetch(`${base.replace(/\/$/, "")}/auth/v1/user`, {
        headers: { apikey: anonKey, Authorization: `Bearer ${supabaseAccessToken}` },
      });
      if (!res.ok) return { status: "invalid_session" };
      const user = (await res.json()) as { id?: unknown };
      legacyUid = typeof user.id === "string" ? user.id : undefined;
    } catch {
      return { status: "unavailable" };
    }
    if (!legacyUid) return { status: "invalid_session" };
    return await ctx.runMutation(internal.account.attachLegacy, {
      legacyUid,
      tokenIdentifier: identity.tokenIdentifier,
      isAnonymous: isAnonymousIdentity(identity),
    });
  },
});
