import type { Doc } from "../_generated/dataModel";
import { iso } from "./time";

// Row shapes identical to the Postgres/PostgREST JSON the Flutter models
// parse (lib/data/models/*): snake_case keys, `id` strings, ISO timestamps,
// explicit nulls.

export function profileRow(p: Doc<"profiles">) {
  return {
    id: p._id,
    nickname: p.nickname,
    photo_url: p.photoUrl ?? null,
    is_anonymous: p.isAnonymous,
    rating: p.rating,
    rated_games: p.ratedGames,
    wins: p.wins,
    losses: p.losses,
    draws: p.draws,
    points: p.points,
    created_at: iso(p.createdAt),
    updated_at: iso(p.updatedAt),
  };
}

export function leaderboardRow(p: Doc<"profiles">) {
  return {
    uid: p._id,
    nickname: p.nickname,
    photo_url: p.photoUrl ?? null,
    rating: p.rating,
    points: p.points,
    rated_games: p.ratedGames,
    wins: p.wins,
    losses: p.losses,
    draws: p.draws,
  };
}

export function gameRow(g: Doc<"games">) {
  return {
    id: g._id,
    status: g.status,
    preset: g.preset,
    board_size: g.boardSize,
    backward_capture: g.backwardCapture,
    flying_king: g.flyingKing,
    majority_capture: g.majorityCapture,
    is_private: g.isPrivate,
    allow_social_join: g.allowSocialJoin,
    rated: g.rated,
    host_uid: g.hostUid ?? null,
    state: g.state ?? null,
    white_bank_ms: g.whiteBankMs,
    black_bank_ms: g.blackBankMs,
    turn_started_at: iso(g.turnStartedAt),
    turn_deadline_at: iso(g.turnDeadlineAt),
    last_move: g.lastMove ?? null,
    draw_offer_color: g.drawOfferColor ?? null,
    result: g.result ?? null,
    result_reason: g.resultReason ?? null,
    winner_uid: g.winnerUid ?? null,
    rematch_requested_by: g.rematchRequestedBy ?? null,
    rematch_game_id: g.rematchGameId ?? null,
    vs_pc: g.vsPc,
    ai_level: g.aiLevel ?? null,
    allow_undo: g.allowUndo,
    tournament_id: g.tournamentId ?? null,
    created_at: iso(g.createdAt),
    started_at: iso(g.startedAt),
    finished_at: iso(g.finishedAt),
    updated_at: iso(g.updatedAt),
  };
}

export function gamePlayerRow(p: Doc<"gamePlayers">) {
  return {
    game_id: p.gameId,
    seat: p.seat,
    uid: p.uid ?? null,
    nickname: p.nickname,
    photo_url: p.photoUrl ?? null,
    color: p.color ?? null,
    connected: p.connected,
    last_seen_at: iso(p.lastSeenAt),
    rating_before: p.ratingBefore ?? null,
    rating_after: p.ratingAfter ?? null,
    is_bot: p.isBot,
  };
}

export function watcherRow(w: Doc<"gameWatchers">) {
  return {
    game_id: w.gameId,
    uid: w.uid,
    nickname: w.nickname,
    photo_url: w.photoUrl ?? null,
    rating: w.rating,
    joined_at: iso(w.joinedAt),
    last_seen_at: iso(w.lastSeenAt),
  };
}

export function emoteRow(e: Doc<"gameEmotes">) {
  return {
    id: e._id,
    game_id: e.gameId,
    uid: e.uid,
    emoji: e.emoji,
    created_at: iso(e.createdAt),
  };
}

export function inviteRow(i: Doc<"invites">) {
  return {
    id: i._id,
    game_id: i.gameId,
    inviter_uid: i.inviterUid,
    invitee_uid: i.inviteeUid,
    inviter_nickname: i.inviterNickname,
    status: i.status,
    created_at: iso(i.createdAt),
    expires_at: iso(i.expiresAt),
  };
}

export function playerListRow(p: {
  uid: string;
  nickname: string;
  photoUrl?: string;
  rating: number;
}) {
  return {
    uid: p.uid,
    nickname: p.nickname,
    photo_url: p.photoUrl ?? null,
    rating: p.rating,
  };
}
