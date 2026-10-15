import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import { internalMutation, mutation, query, type QueryCtx } from "./_generated/server";
import { currentProfile, requirePlayer, requireProfile } from "./lib/auth";
import { assertNotBlockedForPlay } from "./lib/blocks";
import { fail } from "./lib/errors";
import { iso } from "./lib/time";
import {
  LOBBY_STALE_MS,
  advanceTournament,
  stageMatches,
  tournamentPlayers,
  tryStartTournament,
} from "./lib/tournaments";
import { isBusy, listOnlinePlayers } from "./social";

// Tournaments (0018-0023): lobby presence, invites with cooldown, reminder
// opt-ins, bracket reads, and the scheduled start / advance / sweep jobs.

const INVITE_TTL_MS = 3 * 60_000;
const DECLINE_COOLDOWN_MS = 30 * 60_000;

function tournamentRow(t: Doc<"tournaments">) {
  return {
    id: t._id,
    number: t.number,
    status: t.status,
    stage: t.stage,
    participant_count: t.participantCount,
    preset: t.preset,
    created_at: iso(t.createdAt),
    finished_at: iso(t.finishedAt),
    winner_uid: t.winnerUid ?? null,
    second_uid: t.secondUid ?? null,
    third_uid: t.thirdUid ?? null,
  };
}

function tournamentPlayerRow(p: Doc<"tournamentPlayers">) {
  return {
    tournament_id: p.tournamentId,
    uid: p.uid,
    nickname: p.nickname,
    photo_url: p.photoUrl ?? null,
    rating: p.rating,
    join_order: p.joinOrder,
    points: p.points,
    eliminated: p.eliminated,
    final_rank: p.finalRank ?? null,
  };
}

function matchRow(m: Doc<"tournamentMatches">) {
  return {
    id: m._id,
    tournament_id: m.tournamentId,
    stage: m.stage,
    match_index: m.matchIndex,
    p1_uid: m.p1Uid,
    p2_uid: m.p2Uid,
    game_id: m.gameId ?? null,
    winner_uid: m.winnerUid ?? null,
    status: m.status,
    created_at: iso(m.createdAt),
  };
}

// ---------------------------------------------------------------------
// Lobby
// ---------------------------------------------------------------------

async function lobbyRow(ctx: QueryCtx, uid: Id<"profiles">) {
  return await ctx.db
    .query("tournamentLobby")
    .withIndex("by_uid", (q) => q.eq("uid", uid))
    .unique();
}

export const joinLobby = mutation({
  args: {},
  handler: async (ctx) => {
    const me = await requirePlayer(ctx);
    await assertNotBlockedForPlay(ctx, me._id);
    const now = Date.now();
    const row = await lobbyRow(ctx, me._id);
    if (row) await ctx.db.patch("tournamentLobby", row._id, { lastSeenAt: now });
    else {
      await ctx.db.insert("tournamentLobby", {
        uid: me._id,
        nickname: me.nickname,
        photoUrl: me.photoUrl,
        rating: me.rating,
        joinedAt: now,
        lastSeenAt: now,
      });
    }
    return { joined: true };
  },
});

export const touchLobby = mutation({
  args: {},
  handler: async (ctx) => {
    const me = await currentProfile(ctx);
    const row = me ? await lobbyRow(ctx, me._id) : null;
    if (row) await ctx.db.patch("tournamentLobby", row._id, { lastSeenAt: Date.now() });
    return null;
  },
});

export const leaveLobby = mutation({
  args: {},
  handler: async (ctx) => {
    const me = await currentProfile(ctx);
    const row = me ? await lobbyRow(ctx, me._id) : null;
    if (row) await ctx.db.delete("tournamentLobby", row._id);
    return null;
  },
});

/** Lobby members, earliest joiner first (live). */
export const lobby = query({
  args: {},
  handler: async (ctx) => {
    const rows = await ctx.db.query("tournamentLobby").withIndex("by_joined").take(500);
    return rows.map((r) => ({
      uid: r.uid,
      nickname: r.nickname,
      photo_url: r.photoUrl ?? null,
      rating: r.rating,
      joined_at: iso(r.joinedAt),
      last_seen_at: iso(r.lastSeenAt),
    }));
  },
});

// ---------------------------------------------------------------------
// Reminder opt-ins ("Leave & notify me")
// ---------------------------------------------------------------------

export const optInNotify = mutation({
  args: { token: v.string() },
  handler: async (ctx, { token }) => {
    const me = await requireProfile(ctx);
    if (token.length < 20 || token.length > 4096) fail("bad_token");
    const row = await ctx.db
      .query("tournamentNotifyOptins")
      .withIndex("by_uid", (q) => q.eq("uid", me._id))
      .unique();
    const fields = { fcmToken: token, createdAt: Date.now() };
    if (row) await ctx.db.patch("tournamentNotifyOptins", row._id, fields);
    else await ctx.db.insert("tournamentNotifyOptins", { uid: me._id, ...fields });
    return null;
  },
});

export const cancelNotify = mutation({
  args: {},
  handler: async (ctx) => {
    const me = await currentProfile(ctx);
    if (!me) return null;
    const row = await ctx.db
      .query("tournamentNotifyOptins")
      .withIndex("by_uid", (q) => q.eq("uid", me._id))
      .unique();
    if (row) await ctx.db.delete("tournamentNotifyOptins", row._id);
    return null;
  },
});

// ---------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------

/** `my_tournament_state`: the caller's live tournament and current game. */
export const myState = query({
  args: {},
  handler: async (ctx) => {
    const me = await currentProfile(ctx);
    if (!me) return { tournament_id: null, game_id: null };
    const entries = await ctx.db
      .query("tournamentPlayers")
      .withIndex("by_uid", (q) => q.eq("uid", me._id))
      .order("desc")
      .take(20);
    let live: Doc<"tournaments"> | null = null;
    for (const e of entries) {
      const t = await ctx.db.get("tournaments", e.tournamentId);
      if (t && t.status !== "finished" && (!live || t.createdAt > live.createdAt)) live = t;
    }
    if (!live) return { tournament_id: null, game_id: null };
    const matches = await stageMatches(ctx, live._id, live.stage);
    const third = live.stage === "f" ? await stageMatches(ctx, live._id, "third") : [];
    for (const m of [...matches, ...third]) {
      if (m.status === "finished" || !m.gameId) continue;
      if (m.p1Uid !== me._id && m.p2Uid !== me._id) continue;
      const game = await ctx.db.get("games", m.gameId);
      if (game?.status === "playing") return { tournament_id: live._id, game_id: game._id };
    }
    return { tournament_id: live._id, game_id: null };
  },
});

/** Tournaments newest first, with the winner's identity attached. */
export const list = query({
  args: { offset: v.optional(v.number()), limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const offset = Math.max(Math.trunc(args.offset ?? 0), 0);
    const limit = Math.min(Math.max(Math.trunc(args.limit ?? 20), 1), 50);
    const rows = await ctx.db
      .query("tournaments")
      .withIndex("by_created")
      .order("desc")
      .take(offset + limit);
    return await Promise.all(
      rows.slice(offset).map(async (t) => {
        let winner: Doc<"tournamentPlayers"> | null = null;
        if (t.status === "finished" && t.winnerUid) {
          winner = await ctx.db
            .query("tournamentPlayers")
            .withIndex("by_tournament_and_uid", (q) =>
              q.eq("tournamentId", t._id).eq("uid", t.winnerUid!),
            )
            .unique();
        }
        return {
          ...tournamentRow(t),
          winner_nickname: winner?.nickname ?? null,
          winner_photo_url: winner?.photoUrl ?? null,
        };
      }),
    );
  },
});

export const detail = query({
  args: { tournamentId: v.string() },
  handler: async (ctx, { tournamentId }) => {
    const id = ctx.db.normalizeId("tournaments", tournamentId);
    const t = id ? await ctx.db.get("tournaments", id) : null;
    if (!t) return null;
    const players = await tournamentPlayers(ctx, t._id);
    const matches = await ctx.db
      .query("tournamentMatches")
      .withIndex("by_tournament_and_stage", (q) => q.eq("tournamentId", t._id))
      .take(1024);
    matches.sort((a, b) => a.createdAt - b.createdAt || a._creationTime - b._creationTime);
    return {
      tournament: tournamentRow(t),
      players: players.map(tournamentPlayerRow),
      matches: matches.map(matchRow),
    };
  },
});

/** Live matches of a tournament (bracket view). */
export const matches = query({
  args: { tournamentId: v.string() },
  handler: async (ctx, { tournamentId }) => {
    const id = ctx.db.normalizeId("tournaments", tournamentId);
    if (!id) return [];
    const rows = await ctx.db
      .query("tournamentMatches")
      .withIndex("by_tournament_and_stage", (q) => q.eq("tournamentId", id))
      .take(1024);
    rows.sort((a, b) => a.createdAt - b.createdAt || a._creationTime - b._creationTime);
    return rows.map(matchRow);
  },
});

// ---------------------------------------------------------------------
// Invites
// ---------------------------------------------------------------------

/** `_tournament_invitable`: no recent decline, no pending invite. */
async function invitable(ctx: QueryCtx, uid: Id<"profiles">, now: number) {
  const recent = await ctx.db
    .query("tournamentInvites")
    .withIndex("by_invitee_and_created", (q) =>
      q.eq("inviteeUid", uid).gt("createdAt", now - DECLINE_COOLDOWN_MS - INVITE_TTL_MS),
    )
    .take(50);
  return !recent.some(
    (i) =>
      (i.status === "declined" && (i.respondedAt ?? 0) > now - DECLINE_COOLDOWN_MS) ||
      (i.status === "pending" && i.expiresAt > now),
  );
}

export const listInvitablePlayers = query({
  args: {
    search: v.optional(v.union(v.string(), v.null())),
    offset: v.optional(v.number()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) =>
    await listOnlinePlayers(
      ctx,
      args,
      async (uid, now) => !(await lobbyRow(ctx, uid)) && (await invitable(ctx, uid, now)),
      { requireIdle: false },
    ),
});

export const invite = mutation({
  args: { invitees: v.array(v.string()) },
  handler: async (ctx, { invitees }) => {
    const me = await requirePlayer(ctx);
    await assertNotBlockedForPlay(ctx, me._id);
    const now = Date.now();
    let sent = 0;
    for (const raw of invitees.slice(0, 100)) {
      const uid = ctx.db.normalizeId("profiles", raw);
      if (!uid || uid === me._id) continue;
      if (await lobbyRow(ctx, uid)) continue;
      if (!(await invitable(ctx, uid, now))) continue;
      await ctx.db.insert("tournamentInvites", {
        inviterUid: me._id,
        inviteeUid: uid,
        inviterNickname: me.nickname,
        status: "pending",
        createdAt: now,
        expiresAt: now + INVITE_TTL_MS,
      });
      sent++;
    }
    return { sent };
  },
});

export const respondInvite = mutation({
  args: { inviteId: v.string(), accept: v.boolean() },
  handler: async (ctx, { inviteId, accept }) => {
    const me = await requireProfile(ctx);
    const id = ctx.db.normalizeId("tournamentInvites", inviteId);
    const row = id ? await ctx.db.get("tournamentInvites", id) : null;
    if (!row || row.inviteeUid !== me._id) fail("invite_not_found");
    if (row.status !== "pending") return { status: row.status };
    const now = Date.now();
    if (!accept) {
      await ctx.db.patch("tournamentInvites", row._id, { status: "declined", respondedAt: now });
      return { status: "declined" };
    }
    if (row.expiresAt < now) return { status: "expired" };
    await ctx.db.patch("tournamentInvites", row._id, { status: "accepted", respondedAt: now });
    return { status: "accepted" };
  },
});

/** Tournament invites addressed to the caller (latest 20). */
export const myInvites = query({
  args: {},
  handler: async (ctx) => {
    const me = await currentProfile(ctx);
    if (!me) return [];
    const rows = await ctx.db
      .query("tournamentInvites")
      .withIndex("by_invitee_and_created", (q) => q.eq("inviteeUid", me._id))
      .order("desc")
      .take(20);
    return rows.map((i) => ({
      id: i._id,
      inviter_uid: i.inviterUid,
      invitee_uid: i.inviteeUid,
      inviter_nickname: i.inviterNickname,
      status: i.status,
      created_at: iso(i.createdAt),
      expires_at: iso(i.expiresAt),
      responded_at: iso(i.respondedAt),
    }));
  },
});

// ---------------------------------------------------------------------
// Scheduled jobs
// ---------------------------------------------------------------------

export const advance = internalMutation({
  args: { tournamentId: v.id("tournaments") },
  handler: async (ctx, { tournamentId }) => {
    await advanceTournament(ctx, tournamentId);
    return null;
  },
});

export const tryStart = internalMutation({
  args: {},
  handler: async (ctx) => await tryStartTournament(ctx),
});

export const sweepLobby = internalMutation({
  args: {},
  handler: async (ctx) => {
    const cutoff = Date.now() - LOBBY_STALE_MS;
    const stale = await ctx.db
      .query("tournamentLobby")
      .withIndex("by_last_seen", (q) => q.lt("lastSeenAt", cutoff))
      .take(500);
    for (const row of stale) await ctx.db.delete("tournamentLobby", row._id);
    return null;
  },
});

/** `notify_tournament_soon` (:29 and :59): consumes eligible opt-ins and
 * pushes "starts in 1 minute" through the relay. */
export const notifySoon = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = Date.now();
    const tokens = new Set<string>();
    const optins = await ctx.db.query("tournamentNotifyOptins").take(5000);
    for (const o of optins) {
      if (await lobbyRow(ctx, o.uid)) continue;
      if (await isBusy(ctx, o.uid, now)) continue;
      tokens.add(o.fcmToken);
      await ctx.db.delete("tournamentNotifyOptins", o._id);
    }
    if (tokens.size > 0) {
      await ctx.scheduler.runAfter(0, internal.push.relay, {
        tokens: [...tokens],
        title: "Checkers",
        body: "A tournament starts in 1 minute — tap to join!",
        data: { type: "tournament_soon" },
      });
    }
    return null;
  },
});
