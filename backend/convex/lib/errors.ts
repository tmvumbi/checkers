import { ConvexError } from "convex/values";

/**
 * Throws an application error whose data is the same code string the
 * Postgres RPCs raised (`stale_move`, `profile_required`, ...), so client
 * error handling keeps matching on it.
 */
export function fail(code: string): never {
  throw new ConvexError(code);
}
