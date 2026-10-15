import type { QueryCtx } from "../_generated/server";

export const PUBLIC_CONFIG_KEY = "public";

/** The public remote config object (`app_config` row `public`). */
export async function publicConfig(ctx: QueryCtx): Promise<Record<string, any>> {
  const row = await ctx.db
    .query("appConfig")
    .withIndex("by_key", (q) => q.eq("key", PUBLIC_CONFIG_KEY))
    .unique();
  const config = row?.config;
  return config && typeof config === "object" ? (config as Record<string, any>) : {};
}

function intOr(raw: unknown, fallback: number): number {
  if (typeof raw === "number" && Number.isFinite(raw)) return Math.trunc(raw);
  if (typeof raw === "string" && /^-?[0-9]+$/.test(raw)) return parseInt(raw, 10);
  return fallback;
}

/** Mirrors `_clock_config()`: per-move allowance and starting bank. */
export async function clockConfig(ctx: QueryCtx): Promise<{ turnMs: number; bankMs: number }> {
  const config = await publicConfig(ctx);
  return {
    turnMs: Math.max(intOr(config.turn_ms, 15000), 1000),
    bankMs: Math.max(intOr(config.bank_ms, 300000), 0),
  };
}

/** Mirrors `_point_rule_int()`: non-negative integer rule or the default. */
export function pointRuleInt(config: Record<string, any>, key: string, fallback: number): number {
  const raw = config.points?.[key];
  const text = typeof raw === "number" ? String(raw) : raw;
  if (typeof text !== "string" || !/^[0-9]+$/.test(text)) return fallback;
  return Math.min(parseInt(text, 10), 1_000_000);
}

export function pointRules(config: Record<string, any>) {
  return {
    pc_easy_win: pointRuleInt(config, "pc_easy_win", 1),
    pc_medium_win: pointRuleInt(config, "pc_medium_win", 5),
    pc_hard_win: pointRuleInt(config, "pc_hard_win", 10),
    tournament_per_participant: pointRuleInt(config, "tournament_per_participant", 1),
    tournament_bonus: pointRuleInt(config, "tournament_bonus", 0),
  };
}

export function leaderboardMinGames(config: Record<string, any>): number {
  return intOr(config.leaderboard_min_games, 10);
}
