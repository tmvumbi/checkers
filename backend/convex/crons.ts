import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

// Replaces the pg_cron jobs (checkers-sweep, checkers-lobby-sweep,
// checkers-tournaments, checkers-tournament-notify). Times are UTC.
const crons = cronJobs();

crons.interval("online games sweep", { seconds: 30 }, internal.sweeps.onlineGames, {});
crons.interval("tournament lobby sweep", { seconds: 45 }, internal.tournaments.sweepLobby, {});
crons.cron("tournament start", "0,30 * * * *", internal.tournaments.tryStart, {});
crons.cron("tournament reminder", "29,59 * * * *", internal.tournaments.notifySoon, {});

export default crons;
