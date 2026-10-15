import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

// Port of the Supabase schema (supabase/migrations/0001-0038).
//
// Conventions:
// - A player is a `profiles` document; every "uid" field is an
//   Id<"profiles">. The Firebase identity lives only on the profile
//   (`tokenIdentifier`), so claiming a migrated account re-points one row.
// - Timestamps are epoch milliseconds; queries serialize them to ISO
//   strings so the Flutter row parsers keep working unchanged.
// - `legacyId` keeps the Supabase primary key on migrated rows.

const color = v.union(v.literal("white"), v.literal("black"));
const gameStatus = v.union(
  v.literal("waiting"),
  v.literal("playing"),
  v.literal("finished"),
  v.literal("abandoned"),
);
const blockLevel = v.union(v.literal("soft"), v.literal("full"));
const deviceKind = v.union(
  v.literal("android_ssaid"),
  v.literal("ios_keychain"),
  v.literal("ios_idfv"),
);

export default defineSchema({
  profiles: defineTable({
    tokenIdentifier: v.optional(v.string()),
    nickname: v.string(),
    photoUrl: v.optional(v.string()),
    photoStorageId: v.optional(v.id("_storage")),
    isAnonymous: v.boolean(),
    rating: v.number(),
    ratedGames: v.number(),
    wins: v.number(),
    losses: v.number(),
    draws: v.number(),
    points: v.number(),
    createdAt: v.number(),
    updatedAt: v.number(),
    legacyId: v.optional(v.string()),
  })
    .index("by_token", ["tokenIdentifier"])
    .index("by_created", ["createdAt"])
    .index("by_legacy_id", ["legacyId"])
    .index("by_rating", ["rating"])
    .index("by_points_and_rating", ["points", "rating"]),

  // Provider identities of migrated Supabase accounts (auth.identities):
  // a Google/Apple sign-in whose provider subject matches re-claims the
  // imported profile even without a local legacy session.
  legacyIdentities: defineTable({
    provider: v.string(),
    subject: v.string(),
    profileId: v.id("profiles"),
  })
    .index("by_provider_and_subject", ["provider", "subject"])
    .index("by_profile", ["profileId"]),

  games: defineTable({
    status: gameStatus,
    preset: v.string(),
    boardSize: v.number(),
    backwardCapture: v.boolean(),
    flyingKing: v.boolean(),
    majorityCapture: v.boolean(),
    isPrivate: v.boolean(),
    allowSocialJoin: v.boolean(),
    rated: v.boolean(),
    hostUid: v.optional(v.id("profiles")),
    state: v.optional(v.any()),
    whiteBankMs: v.number(),
    blackBankMs: v.number(),
    turnStartedAt: v.optional(v.number()),
    turnDeadlineAt: v.optional(v.number()),
    lastMove: v.optional(v.any()),
    drawOfferColor: v.optional(color),
    result: v.optional(v.string()),
    resultReason: v.optional(v.string()),
    winnerUid: v.optional(v.id("profiles")),
    rematchRequestedBy: v.optional(v.id("profiles")),
    rematchGameId: v.optional(v.id("games")),
    vsPc: v.boolean(),
    aiLevel: v.optional(v.string()),
    allowUndo: v.boolean(),
    tournamentId: v.optional(v.id("tournaments")),
    // Lower-cased seated nicknames, for the recent-games search.
    playerSearch: v.optional(v.string()),
    timeoutJobId: v.optional(v.id("_scheduled_functions")),
    createdAt: v.number(),
    startedAt: v.optional(v.number()),
    finishedAt: v.optional(v.number()),
    updatedAt: v.number(),
    legacyId: v.optional(v.string()),
  })
    .index("by_status_and_private_and_preset", ["status", "isPrivate", "preset"])
    .index("by_status_and_started", ["status", "startedAt"])
    .index("by_status_and_deadline", ["status", "turnDeadlineAt"])
    .index("by_status_and_private_and_finished", [
      "status",
      "isPrivate",
      "finishedAt",
    ])
    .index("by_vs_pc_and_status_and_updated", ["vsPc", "status", "updatedAt"])
    .index("by_tournament", ["tournamentId"])
    .index("by_created", ["createdAt"])
    .index("by_legacy_id", ["legacyId"]),

  gamePlayers: defineTable({
    gameId: v.id("games"),
    seat: v.number(),
    uid: v.optional(v.id("profiles")),
    nickname: v.string(),
    photoUrl: v.optional(v.string()),
    color: v.optional(color),
    connected: v.boolean(),
    lastSeenAt: v.number(),
    ratingBefore: v.optional(v.number()),
    ratingAfter: v.optional(v.number()),
    isBot: v.boolean(),
    // Mirror of games.status so "is this player busy" is one index read.
    gameStatus: gameStatus,
  })
    .index("by_game_and_seat", ["gameId", "seat"])
    .index("by_game_and_uid", ["gameId", "uid"])
    .index("by_uid_and_status", ["uid", "gameStatus"]),

  gameMoves: defineTable({
    gameId: v.id("games"),
    ply: v.number(),
    color: color,
    move: v.any(),
    msSpent: v.number(),
    playedAt: v.number(),
  }).index("by_game_and_ply", ["gameId", "ply"]),

  playerPresence: defineTable({
    uid: v.id("profiles"),
    nickname: v.string(),
    photoUrl: v.optional(v.string()),
    rating: v.number(),
    busyMode: v.string(),
    lastActiveAt: v.number(),
  })
    .index("by_uid", ["uid"])
    .index("by_last_active", ["lastActiveAt"]),

  invites: defineTable({
    gameId: v.id("games"),
    inviterUid: v.id("profiles"),
    inviteeUid: v.id("profiles"),
    inviterNickname: v.string(),
    status: v.string(),
    createdAt: v.number(),
    expiresAt: v.number(),
  })
    .index("by_invitee", ["inviteeUid"])
    .index("by_inviter", ["inviterUid"])
    .index("by_game", ["gameId"])
    .index("by_status_and_expires", ["status", "expiresAt"]),

  appConfig: defineTable({
    key: v.string(),
    config: v.any(),
  }).index("by_key", ["key"]),

  feedback: defineTable({
    uid: v.id("profiles"),
    text: v.string(),
    createdAt: v.number(),
    handledAt: v.optional(v.number()),
  }).index("by_created", ["createdAt"]),

  gameWatchers: defineTable({
    gameId: v.id("games"),
    uid: v.id("profiles"),
    nickname: v.string(),
    photoUrl: v.optional(v.string()),
    rating: v.number(),
    joinedAt: v.number(),
    lastSeenAt: v.number(),
  })
    .index("by_game_and_uid", ["gameId", "uid"])
    .index("by_game_and_joined", ["gameId", "joinedAt"])
    .index("by_uid", ["uid"])
    .index("by_last_seen", ["lastSeenAt"]),

  gameEmotes: defineTable({
    gameId: v.id("games"),
    uid: v.id("profiles"),
    emoji: v.string(),
    createdAt: v.number(),
  })
    .index("by_game", ["gameId"])
    .index("by_game_and_uid", ["gameId", "uid"]),

  playerMessages: defineTable({
    type: v.union(v.literal("public"), v.literal("private")),
    language: v.union(v.literal("en"), v.literal("fr")),
    targetUid: v.optional(v.id("profiles")),
    htmlText: v.optional(v.string()),
    imageUrl: v.optional(v.string()),
    linkUrl: v.optional(v.string()),
    publishAt: v.number(),
    expiresAt: v.number(),
    enabled: v.boolean(),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_type_and_enabled", ["type", "enabled"])
    .index("by_target", ["targetUid"]),

  playerBlocks: defineTable({
    uid: v.id("profiles"),
    level: blockLevel,
    reason: v.optional(v.string()),
    expiresAt: v.optional(v.number()),
    createdAt: v.number(),
    revokedAt: v.optional(v.number()),
  }).index("by_uid", ["uid"]),

  playerDevices: defineTable({
    uid: v.id("profiles"),
    kind: deviceKind,
    value: v.string(),
    firstSeenAt: v.number(),
    lastSeenAt: v.number(),
  })
    .index("by_uid_and_kind_and_value", ["uid", "kind", "value"])
    .index("by_kind_and_value", ["kind", "value"]),

  blockedDevices: defineTable({
    blockId: v.id("playerBlocks"),
    kind: v.string(),
    value: v.string(),
    level: blockLevel,
    expiresAt: v.optional(v.number()),
  })
    .index("by_block", ["blockId"])
    .index("by_kind_and_value", ["kind", "value"]),

  tournamentLobby: defineTable({
    uid: v.id("profiles"),
    nickname: v.string(),
    photoUrl: v.optional(v.string()),
    rating: v.number(),
    joinedAt: v.number(),
    lastSeenAt: v.number(),
  })
    .index("by_uid", ["uid"])
    .index("by_joined", ["joinedAt"])
    .index("by_last_seen", ["lastSeenAt"]),

  tournaments: defineTable({
    number: v.number(),
    status: v.union(
      v.literal("elimination"),
      v.literal("knockout"),
      v.literal("finished"),
    ),
    stage: v.string(),
    participantCount: v.number(),
    preset: v.string(),
    createdAt: v.number(),
    finishedAt: v.optional(v.number()),
    winnerUid: v.optional(v.id("profiles")),
    secondUid: v.optional(v.id("profiles")),
    thirdUid: v.optional(v.id("profiles")),
    legacyId: v.optional(v.string()),
  })
    .index("by_number", ["number"])
    .index("by_created", ["createdAt"])
    .index("by_status_and_created", ["status", "createdAt"])
    .index("by_legacy_id", ["legacyId"]),

  tournamentPlayers: defineTable({
    tournamentId: v.id("tournaments"),
    uid: v.id("profiles"),
    nickname: v.string(),
    photoUrl: v.optional(v.string()),
    rating: v.number(),
    joinOrder: v.number(),
    points: v.number(),
    eliminated: v.boolean(),
    finalRank: v.optional(v.number()),
  })
    .index("by_tournament_and_uid", ["tournamentId", "uid"])
    .index("by_uid", ["uid"]),

  tournamentMatches: defineTable({
    tournamentId: v.id("tournaments"),
    stage: v.string(),
    matchIndex: v.number(),
    p1Uid: v.id("profiles"),
    p2Uid: v.id("profiles"),
    gameId: v.optional(v.id("games")),
    winnerUid: v.optional(v.id("profiles")),
    status: v.union(v.literal("playing"), v.literal("finished")),
    createdAt: v.number(),
  })
    .index("by_tournament_and_stage", ["tournamentId", "stage"])
    .index("by_game", ["gameId"]),

  tournamentInvites: defineTable({
    inviterUid: v.id("profiles"),
    inviteeUid: v.id("profiles"),
    inviterNickname: v.string(),
    status: v.union(
      v.literal("pending"),
      v.literal("accepted"),
      v.literal("declined"),
    ),
    createdAt: v.number(),
    expiresAt: v.number(),
    respondedAt: v.optional(v.number()),
  }).index("by_invitee_and_created", ["inviteeUid", "createdAt"]),

  tournamentNotifyOptins: defineTable({
    uid: v.id("profiles"),
    fcmToken: v.string(),
    createdAt: v.number(),
  }).index("by_uid", ["uid"]),

  adCustomers: defineTable({
    name: v.string(),
    contact: v.optional(v.string()),
    notes: v.optional(v.string()),
    createdAt: v.number(),
    legacyId: v.optional(v.string()),
  }).index("by_legacy_id", ["legacyId"]),

  adCampaigns: defineTable({
    customerId: v.optional(v.id("adCustomers")),
    name: v.string(),
    bannerUrl: v.string(),
    targetUrl: v.string(),
    pieceWhiteManUrl: v.optional(v.string()),
    pieceWhiteKingUrl: v.optional(v.string()),
    pieceBlackManUrl: v.optional(v.string()),
    pieceBlackKingUrl: v.optional(v.string()),
    // Calendar days as "YYYY-MM-DD" (UTC), like the Postgres date columns.
    startsAt: v.string(),
    endsAt: v.optional(v.string()),
    active: v.boolean(),
    maxDailyPrints: v.optional(v.number()),
    createdAt: v.number(),
    legacyId: v.optional(v.string()),
  })
    .index("by_active", ["active"])
    .index("by_legacy_id", ["legacyId"]),

  adDailyStats: defineTable({
    campaignId: v.id("adCampaigns"),
    day: v.string(),
    prints: v.number(),
    clicks: v.number(),
  })
    .index("by_campaign_and_day", ["campaignId", "day"])
    .index("by_day", ["day"]),

  pointAwards: defineTable({
    uid: v.id("profiles"),
    awardType: v.union(v.literal("pc_win"), v.literal("tournament_win")),
    sourceId: v.string(),
    points: v.number(),
    metadata: v.any(),
    createdAt: v.number(),
  }).index("by_type_and_source_and_uid", ["awardType", "sourceId", "uid"]),

  pushDevices: defineTable({
    uid: v.id("profiles"),
    fcmToken: v.string(),
    platform: v.union(v.literal("android"), v.literal("ios"), v.literal("unknown")),
    createdAt: v.number(),
    lastSeenAt: v.number(),
    disabledAt: v.optional(v.number()),
  })
    .index("by_token", ["fcmToken"])
    .index("by_uid", ["uid"])
    .index("by_last_seen", ["lastSeenAt"]),

  pushBroadcasts: defineTable({
    title: v.string(),
    body: v.string(),
    platform: v.union(v.literal("all"), v.literal("android"), v.literal("ios")),
    activeWithinHours: v.optional(v.number()),
    targetedCount: v.number(),
    sentCount: v.number(),
    failedCount: v.number(),
    status: v.union(
      v.literal("sending"),
      v.literal("sent"),
      v.literal("partial"),
      v.literal("failed"),
    ),
    error: v.optional(v.string()),
    createdAt: v.number(),
    completedAt: v.optional(v.number()),
  }).index("by_created", ["createdAt"]),
});
