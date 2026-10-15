import { query } from "./_generated/server";
import { publicConfig } from "./lib/config";

/** Public remote config (version gate, AdMob, clocks, points rules).
 * Readable before sign-in, like the anon-readable `app_config` row. */
export const getPublic = query({
  args: {},
  handler: async (ctx) => await publicConfig(ctx),
});
