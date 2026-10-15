import { v } from "convex/values";
import type { Id } from "./_generated/dataModel";
import { mutation, query, type QueryCtx } from "./_generated/server";
import { currentProfile, requirePlayer, requireProfile } from "./lib/auth";
import { fail } from "./lib/errors";
import { assertPreset, getGame, insertWaitingGame, seatPlayer, seatOf, startGame } from "./lib/games";
import { inviteRow, playerListRow } from "./lib/serialize";

// Private invites, share-link (social) games and the available-players
// directory (0005, 0023, 0031).

export const PRESENCE_STALE_MS = 3 * 60_000;
export const WATCHER_STALE_MS = 90_000;
const INVITE_TTL_MS = 60_000;

/** True when [uid] is seated in a live game or actively watching one. */
export async function isBusy(ctx: QueryCtx, uid: Id<"profiles">, now: number) {
  const playing = await ctx.db
    .query("gamePlayers")
    .withIndex("by_uid_and_status", (q) => q.eq("uid", uid).eq("gameStatus", "playing"))
    .first();
  if (playing) return true;
  const watching = await ctx.db
    .query("gameWatchers")
    .withIndex("by_uid", (q) => q.eq("uid", uid))
    .take(10);
  return watching.some((w) => w.lastSeenAt > now - WATCHER_STALE_MS);
}

/**
 * Online players matching the shared directory filters, most recently
 * active first. [extra] applies list-specific eligibility.
 */
export async function listOnlinePlayers(
  ctx: QueryCtx,
  args: { search?: string | null; offset?: number; limit?: number },
  extra: (uid: Id<"profiles">, now: number) => Promise<boolean>,
  options: { requireIdle: boolean },
) {
  const me = await currentProfile(ctx);
  if (!me) return [];
  const now = Date.now();
  const offset = Math.max(Math.trunc(args.offset ?? 0), 0);
  const limit = Math.min(Math.max(Math.trunc(args.limit ?? 20), 1), 50);
  const needle = (args.search ?? "").trim().toLowerCase();
  const out = [];
  let scanned = 0;
  for await (const p of ctx.db
    .query("playerPresence")
    .withIndex("by_last_active", (q) => q.gt("lastActiveAt", now - PRESENCE_STALE_MS))
    .order("desc")) {
    if (++scanned > 2000 || out.length >= offset + limit) break;
    if (p.uid === me._id || p.nickname === "") continue;
    if (options.requireIdle && p.busyMode !== "idle") continue;
    if (needle && !p.nickname.toLowerCase().includes(needle)) continue;
    if (await isBusy(ctx, p.uid, now)) continue;
    if (!(await extra(p.uid, now))) continue;
    out.push(p);
  }
  return out.slice(offset).map((p) => playerListRow({ ...p, uid: p.uid }));
}

/** `list_available_players`: idle online players for a game invite. */
export const listAvailablePlayers = query({
  args: {
    search: v.optional(v.union(v.string(), v.null())),
    offset: v.optional(v.number()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) =>
    await listOnlinePlayers(ctx, args, async () => true, { requireIdle: true }),
});

/** `create_private_invite`: an unrated private lobby plus an invite. */
export const createPrivateInvite = mutation({
  args: { inviteeUid: v.string(), preset: v.string() },
  handler: async (ctx, args) => {
    assertPreset(args.preset);
    const me = await requirePlayer(ctx);
    const invitee = ctx.db.normalizeId("profiles", args.inviteeUid);
    if (!invitee) fail("invite_not_found");
    if (invitee === me._id) fail("cannot_invite_self");
    const gameId = await insertWaitingGame(ctx, {
      preset: args.preset,
      hostUid: me._id,
      isPrivate: true,
      rated: false,
    });
    const game = (await ctx.db.get("games", gameId))!;
    await seatPlayer(ctx, game, { seat: 0, uid: me._id, nickname: me.nickname, photoUrl: me.photoUrl });
    const now = Date.now();
    const inviteId = await ctx.db.insert("invites", {
      gameId,
      inviterUid: me._id,
      inviteeUid: invitee,
      inviterNickname: me.nickname,
      status: "pending",
      createdAt: now,
      expiresAt: now + INVITE_TTL_MS,
    });
    return { game_id: gameId, invite_id: inviteId };
  },
});

/** `respond_invite`. Accepting takes seat 1 and starts the game. */
export const respondInvite = mutation({
  args: { inviteId: v.string(), accept: v.boolean() },
  handler: async (ctx, { inviteId, accept }) => {
    const me = await requireProfile(ctx);
    const id = ctx.db.normalizeId("invites", inviteId);
    const invite = id ? await ctx.db.get("invites", id) : null;
    if (!invite || invite.inviteeUid !== me._id) fail("invite_not_found");
    const now = Date.now();
    if (invite.status !== "pending" || invite.expiresAt < now) {
      await ctx.db.patch("invites", invite._id, { status: "expired" });
      return { status: "expired" };
    }
    if (!accept) {
      await ctx.db.patch("invites", invite._id, { status: "declined" });
      return { status: "declined" };
    }
    const game = await ctx.db.get("games", invite.gameId);
    if (!game || game.status !== "waiting") {
      await ctx.db.patch("invites", invite._id, { status: "expired" });
      return { status: "expired" };
    }
    await seatPlayer(ctx, game, { seat: 1, uid: me._id, nickname: me.nickname, photoUrl: me.photoUrl });
    await startGame(ctx, game._id);
    await ctx.db.patch("invites", invite._id, { status: "accepted" });
    return { status: "accepted", game_id: game._id };
  },
});

/** Invites addressed to the caller (latest 20); drives the invite popup. */
export const myInvites = query({
  args: {},
  handler: async (ctx) => {
    const me = await currentProfile(ctx);
    if (!me) return [];
    const rows = await ctx.db
      .query("invites")
      .withIndex("by_invitee", (q) => q.eq("inviteeUid", me._id))
      .order("desc")
      .take(20);
    return rows.map(inviteRow);
  },
});

/** `create_social_game`: a private lobby joinable through a share link. */
export const createSocialGame = mutation({
  args: { preset: v.string() },
  handler: async (ctx, { preset }) => {
    assertPreset(preset);
    const me = await requirePlayer(ctx);
    const gameId = await insertWaitingGame(ctx, {
      preset,
      hostUid: me._id,
      isPrivate: true,
      allowSocialJoin: true,
      rated: false,
    });
    const game = (await ctx.db.get("games", gameId))!;
    await seatPlayer(ctx, game, { seat: 0, uid: me._id, nickname: me.nickname, photoUrl: me.photoUrl });
    return { game_id: gameId };
  },
});

/** `join_social_game`: the share-link recipient takes seat 1. */
export const joinSocialGame = mutation({
  args: { gameId: v.string() },
  handler: async (ctx, { gameId }) => {
    const me = await requireProfile(ctx);
    const game = await getGame(ctx, gameId);
    if (!game || !game.allowSocialJoin) fail("game_not_joinable");
    if (await seatOf(ctx, game._id, me._id)) {
      return { status: "already_seated", game_id: game._id };
    }
    if (game.status !== "waiting") fail("game_already_started");
    await seatPlayer(ctx, game, { seat: 1, uid: me._id, nickname: me.nickname, photoUrl: me.photoUrl });
    await startGame(ctx, game._id);
    return { status: "joined", game_id: game._id };
  },
});
