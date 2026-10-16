import type { Id } from "../_generated/dataModel";
import type { QueryCtx } from "../_generated/server";

/** Case- and width-insensitive form of a nickname, used for uniqueness. */
export function nicknameKey(nickname: string): string {
  return nickname.normalize("NFKC").trim().toLocaleLowerCase();
}

/** Whether another player already uses [nickname]. */
export async function nicknameTaken(
  ctx: QueryCtx,
  nickname: string,
  self: Id<"profiles">,
): Promise<boolean> {
  const key = nicknameKey(nickname);
  if (key === "") return false;
  const holders = await ctx.db
    .query("profiles")
    .withIndex("by_nickname_key", (q) => q.eq("nicknameKey", key))
    .take(5);
  return holders.some((p) => p._id !== self);
}
