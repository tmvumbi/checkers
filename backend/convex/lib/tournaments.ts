import { internal } from "../_generated/api";
import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import { pointRuleInt, publicConfig } from "./config";
import { insertWaitingGame, seatPlayer, startGame } from "./games";
import { recordPointAward } from "./points";

// Port of the tournament engine (0018_tournaments + 0019 bracket pairing +
// 0033 tournament-win points). Bracket advancement used to run inside the
// `on_tournament_game_finished` trigger with errors swallowed; here the
// match is closed in the finishing transaction and advancement runs as a
// scheduled mutation, so a failure there can never roll back the game.

export const LOBBY_STALE_MS = 45_000;

export function knockoutStageName(players: number): string {
  if (players === 2) return "f";
  if (players === 4) return "sf";
  if (players === 8) return "qf";
  return `r${players}`;
}

export async function tournamentPlayers(ctx: QueryCtx, tournamentId: Id<"tournaments">) {
  return await ctx.db
    .query("tournamentPlayers")
    .withIndex("by_tournament_and_uid", (q) => q.eq("tournamentId", tournamentId))
    .take(1024);
}

export async function stageMatches(ctx: QueryCtx, tournamentId: Id<"tournaments">, stage: string) {
  return await ctx.db
    .query("tournamentMatches")
    .withIndex("by_tournament_and_stage", (q) =>
      q.eq("tournamentId", tournamentId).eq("stage", stage),
    )
    .take(512);
}

/** Standings order: points, then rating, then lobby join order. */
function byStandings(a: Doc<"tournamentPlayers">, b: Doc<"tournamentPlayers">) {
  return b.points - a.points || b.rating - a.rating || a.joinOrder - b.joinOrder;
}

/** `_create_tournament_game`: a started, rated game for one match. */
async function createTournamentGame(
  ctx: MutationCtx,
  tournament: Doc<"tournaments">,
  matchId: Id<"tournamentMatches">,
  p1: Id<"profiles">,
  p2: Id<"profiles">,
) {
  const gameId = await insertWaitingGame(ctx, {
    preset: tournament.preset,
    hostUid: p1,
    tournamentId: tournament._id,
  });
  const game = (await ctx.db.get("games", gameId))!;
  const firstColor = Math.random() < 0.5 ? "white" : "black";
  for (const [seat, uid] of [p1, p2].entries()) {
    const tp = await ctx.db
      .query("tournamentPlayers")
      .withIndex("by_tournament_and_uid", (q) =>
        q.eq("tournamentId", tournament._id).eq("uid", uid),
      )
      .unique();
    await seatPlayer(
      ctx,
      game,
      {
        seat,
        uid,
        nickname: tp?.nickname ?? "",
        photoUrl: tp?.photoUrl,
        color: seat === 0 ? firstColor : firstColor === "white" ? "black" : "white",
      },
      // Lobby entry already checked blocks; a block landing mid-bracket
      // must not wedge the whole tournament.
      { checkBlock: false },
    );
  }
  await startGame(ctx, gameId);
  await ctx.db.patch("tournamentMatches", matchId, { gameId });
  return gameId;
}

/** `_pair_stage_ordered`: pairs [uids] two by two, keeping their order. */
export async function pairStageOrdered(
  ctx: MutationCtx,
  tournament: Doc<"tournaments">,
  stage: string,
  uids: Id<"profiles">[],
) {
  for (let i = 0; i + 1 < uids.length; i += 2) {
    const matchId = await ctx.db.insert("tournamentMatches", {
      tournamentId: tournament._id,
      stage,
      matchIndex: i / 2 + 1,
      p1Uid: uids[i],
      p2Uid: uids[i + 1],
      status: "playing",
      createdAt: Date.now(),
    });
    await createTournamentGame(ctx, tournament, matchId, uids[i], uids[i + 1]);
  }
}

/** `_pair_stage`: random draw (first round only). */
export async function pairStageRandom(
  ctx: MutationCtx,
  tournament: Doc<"tournaments">,
  stage: string,
  uids: Id<"profiles">[],
) {
  const shuffled = [...uids];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  await pairStageOrdered(ctx, tournament, stage, shuffled);
}

/**
 * Trigger body of `_on_tournament_game_finished`: settles the match
 * (draws go to the tiebreak), awards elimination points, then schedules
 * bracket advancement.
 */
export async function onTournamentGameFinished(ctx: MutationCtx, game: Doc<"games">) {
  if (!game.tournamentId) return;
  const match = await ctx.db
    .query("tournamentMatches")
    .withIndex("by_game", (q) => q.eq("gameId", game._id))
    .unique();
  if (!match || match.status === "finished") return;

  const isDraw = game.result === "draw" || !game.winnerUid;
  let winner: Id<"profiles">;
  if (!isDraw) {
    winner = game.winnerUid!;
  } else {
    const [a, b] = await Promise.all(
      [match.p1Uid, match.p2Uid].map((uid) =>
        ctx.db
          .query("tournamentPlayers")
          .withIndex("by_tournament_and_uid", (q) =>
            q.eq("tournamentId", game.tournamentId!).eq("uid", uid),
          )
          .unique(),
      ),
    );
    winner = a && b ? (byStandings(a, b) <= 0 ? a.uid : b.uid) : match.p1Uid;
  }
  await ctx.db.patch("tournamentMatches", match._id, { winnerUid: winner, status: "finished" });

  if (match.stage === "elimination") {
    const credit = async (uid: Id<"profiles">, pts: number) => {
      const tp = await ctx.db
        .query("tournamentPlayers")
        .withIndex("by_tournament_and_uid", (q) =>
          q.eq("tournamentId", game.tournamentId!).eq("uid", uid),
        )
        .unique();
      if (tp) await ctx.db.patch("tournamentPlayers", tp._id, { points: tp.points + pts });
    };
    if (isDraw) {
      await credit(match.p1Uid, 1);
      await credit(match.p2Uid, 1);
    } else {
      await credit(winner, 3);
    }
  }

  await ctx.scheduler.runAfter(0, internal.tournaments.advance, {
    tournamentId: game.tournamentId,
  });
}

/** `_advance_tournament`: moves the bracket on once a stage is complete. */
export async function advanceTournament(ctx: MutationCtx, tournamentId: Id<"tournaments">) {
  let tournament = await ctx.db.get("tournaments", tournamentId);
  if (!tournament || tournament.status === "finished") return;

  const current = await stageMatches(ctx, tournamentId, tournament.stage);
  const third = tournament.stage === "f" ? await stageMatches(ctx, tournamentId, "third") : [];
  if ([...current, ...third].some((m) => m.status !== "finished")) return;

  const players = await tournamentPlayers(ctx, tournamentId);

  if (tournament.stage === "elimination") {
    const qualify = 1 << Math.floor(Math.log2(tournament.participantCount));
    const ranked = [...players].sort(byStandings);
    for (const [pos, p] of ranked.entries()) {
      await ctx.db.patch("tournamentPlayers", p._id, { eliminated: pos + 1 > qualify });
    }
    // Standings-seeded entry: 1st vs last, 2nd vs second-last, ...
    const qualified = ranked.slice(0, qualify).map((p) => p.uid);
    const seeded: Id<"profiles">[] = [];
    for (let i = 0; i < qualify / 2; i++) {
      seeded.push(qualified[i], qualified[qualify - 1 - i]);
    }
    const stage = knockoutStageName(qualify);
    await ctx.db.patch("tournaments", tournamentId, { status: "knockout", stage });
    tournament = (await ctx.db.get("tournaments", tournamentId))!;
    await pairStageOrdered(ctx, tournament, stage, seeded);
    return;
  }

  if (tournament.stage === "f") {
    const final = current[0];
    const thirdMatch = third[0];
    const second = final ? (final.p1Uid === final.winnerUid ? final.p2Uid : final.p1Uid) : undefined;
    await ctx.db.patch("tournaments", tournamentId, {
      status: "finished",
      stage: "f",
      finishedAt: Date.now(),
      winnerUid: final?.winnerUid,
      secondUid: second,
      thirdUid: thirdMatch?.winnerUid,
    });
    const rank = async (uid: Id<"profiles"> | undefined, finalRank: number) => {
      const p = players.find((x) => x.uid === uid);
      if (p) await ctx.db.patch("tournamentPlayers", p._id, { finalRank });
    };
    if (final) {
      await rank(final.winnerUid, 1);
      await rank(second, 2);
    }
    if (thirdMatch) {
      await rank(thirdMatch.winnerUid, 3);
      await rank(
        thirdMatch.p1Uid === thirdMatch.winnerUid ? thirdMatch.p2Uid : thirdMatch.p1Uid,
        4,
      );
    }
    await awardTournamentWin(ctx, (await ctx.db.get("tournaments", tournamentId))!);
    return;
  }

  // Knockout round done: winners advance in bracket order.
  const ordered = [...current].sort((a, b) => a.matchIndex - b.matchIndex);
  const winners = ordered.map((m) => m.winnerUid!).filter(Boolean);
  for (const p of players) {
    if (!p.eliminated && !winners.includes(p.uid)) {
      await ctx.db.patch("tournamentPlayers", p._id, { eliminated: true });
    }
  }
  if (winners.length === 2) {
    const losers = ordered.map((m) => (m.p1Uid === m.winnerUid ? m.p2Uid : m.p1Uid));
    await ctx.db.patch("tournaments", tournamentId, { stage: "f" });
    tournament = (await ctx.db.get("tournaments", tournamentId))!;
    await pairStageOrdered(ctx, tournament, "f", winners);
    await pairStageOrdered(ctx, tournament, "third", losers);
    return;
  }
  const stage = knockoutStageName(winners.length);
  await ctx.db.patch("tournaments", tournamentId, { stage });
  tournament = (await ctx.db.get("tournaments", tournamentId))!;
  await pairStageOrdered(ctx, tournament, stage, winners);
}

/** The `award_tournament_win_points` trigger. */
async function awardTournamentWin(ctx: MutationCtx, tournament: Doc<"tournaments">) {
  if (!tournament.winnerUid) return;
  const config = await publicConfig(ctx);
  const perParticipant = pointRuleInt(config, "tournament_per_participant", 1);
  const bonus = pointRuleInt(config, "tournament_bonus", 0);
  await recordPointAward(ctx, {
    uid: tournament.winnerUid,
    awardType: "tournament_win",
    sourceId: tournament._id,
    points: Math.max(0, tournament.participantCount * perParticipant + bonus),
    metadata: {
      participant_count: tournament.participantCount,
      per_participant: perParticipant,
      bonus,
    },
  });
}

/** `try_start_tournament`: run every half hour by cron. */
export async function tryStartTournament(ctx: MutationCtx) {
  const now = Date.now();
  for await (const row of ctx.db
    .query("tournamentLobby")
    .withIndex("by_last_seen", (q) => q.lt("lastSeenAt", now - LOBBY_STALE_MS))) {
    await ctx.db.delete("tournamentLobby", row._id);
  }
  const lobby = await ctx.db.query("tournamentLobby").withIndex("by_joined").take(1024);
  if (lobby.length < 4) return { started: false, lobby: lobby.length };

  const take = lobby.length - (lobby.length % 2);
  const entrants = lobby.slice(0, take);
  const last = await ctx.db.query("tournaments").withIndex("by_number").order("desc").first();
  const isPower = (take & (take - 1)) === 0;
  const stage = isPower ? knockoutStageName(take) : "elimination";
  const tournamentId = await ctx.db.insert("tournaments", {
    number: (last?.number ?? 0) + 1,
    status: isPower ? "knockout" : "elimination",
    stage,
    participantCount: take,
    preset: "international",
    createdAt: now,
  });
  for (const [i, entry] of entrants.entries()) {
    await ctx.db.insert("tournamentPlayers", {
      tournamentId,
      uid: entry.uid,
      nickname: entry.nickname,
      photoUrl: entry.photoUrl,
      rating: entry.rating,
      joinOrder: i + 1,
      points: 0,
      eliminated: false,
    });
    await ctx.db.delete("tournamentLobby", entry._id);
  }
  const tournament = (await ctx.db.get("tournaments", tournamentId))!;
  await pairStageRandom(
    ctx,
    tournament,
    stage,
    entrants.map((e) => e.uid),
  );
  return { started: true, tournament_id: tournamentId, players: take };
}
