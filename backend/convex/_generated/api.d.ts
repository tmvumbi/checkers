/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as account from "../account.js";
import type * as admin from "../admin.js";
import type * as ads from "../ads.js";
import type * as blocks from "../blocks.js";
import type * as config from "../config.js";
import type * as crons from "../crons.js";
import type * as feedback from "../feedback.js";
import type * as games from "../games.js";
import type * as gifts from "../gifts.js";
import type * as giftsAdmin from "../giftsAdmin.js";
import type * as http from "../http.js";
import type * as lib_auth from "../lib/auth.js";
import type * as lib_blocks from "../lib/blocks.js";
import type * as lib_config from "../lib/config.js";
import type * as lib_engine from "../lib/engine.js";
import type * as lib_errors from "../lib/errors.js";
import type * as lib_games from "../lib/games.js";
import type * as lib_gifts from "../lib/gifts.js";
import type * as lib_nickname from "../lib/nickname.js";
import type * as lib_points from "../lib/points.js";
import type * as lib_serialize from "../lib/serialize.js";
import type * as lib_time from "../lib/time.js";
import type * as lib_tournaments from "../lib/tournaments.js";
import type * as messages from "../messages.js";
import type * as migration from "../migration.js";
import type * as pcGames from "../pcGames.js";
import type * as presence from "../presence.js";
import type * as profiles from "../profiles.js";
import type * as push from "../push.js";
import type * as social from "../social.js";
import type * as sweeps from "../sweeps.js";
import type * as tournaments from "../tournaments.js";
import type * as watch from "../watch.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  account: typeof account;
  admin: typeof admin;
  ads: typeof ads;
  blocks: typeof blocks;
  config: typeof config;
  crons: typeof crons;
  feedback: typeof feedback;
  games: typeof games;
  gifts: typeof gifts;
  giftsAdmin: typeof giftsAdmin;
  http: typeof http;
  "lib/auth": typeof lib_auth;
  "lib/blocks": typeof lib_blocks;
  "lib/config": typeof lib_config;
  "lib/engine": typeof lib_engine;
  "lib/errors": typeof lib_errors;
  "lib/games": typeof lib_games;
  "lib/gifts": typeof lib_gifts;
  "lib/nickname": typeof lib_nickname;
  "lib/points": typeof lib_points;
  "lib/serialize": typeof lib_serialize;
  "lib/time": typeof lib_time;
  "lib/tournaments": typeof lib_tournaments;
  messages: typeof messages;
  migration: typeof migration;
  pcGames: typeof pcGames;
  presence: typeof presence;
  profiles: typeof profiles;
  push: typeof push;
  social: typeof social;
  sweeps: typeof sweeps;
  tournaments: typeof tournaments;
  watch: typeof watch;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
