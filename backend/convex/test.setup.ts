/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { api } from "./_generated/api";
import schema from "./schema";

export const modules = import.meta.glob("./**/*.*s");

export function newBackend() {
  return convexTest(schema, modules);
}

export type Backend = ReturnType<typeof newBackend>;

/** A signed-in player with a nickname (Firebase identity simulated). */
export async function player(t: Backend, name: string, options: { nickname?: string } = {}) {
  const as = t.withIdentity({
    subject: name,
    issuer: "https://securetoken.google.com/checkers-club",
    tokenIdentifier: `https://securetoken.google.com/checkers-club|${name}`,
  });
  await as.mutation(api.profiles.ensure, {});
  const profile = await as.mutation(api.profiles.updateMine, {
    nickname: options.nickname ?? name,
  });
  return { as, uid: profile.id as string, name };
}

/** International opening moves (white starts): 30→26 then black 19→23. */
export const WHITE_OPENING = { from: 30, path: [26], captured: [] };
export const BLACK_OPENING = { from: 19, path: [23], captured: [] };
