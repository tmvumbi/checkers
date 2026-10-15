import { describe, expect, test } from "vitest";
import vectorFile from "../../supabase/engine/test_vectors.json";
import { CheckersEngineJS as Engine, checkersEngine } from "./lib/engine.js";

// Same Dart-generated vectors as supabase/engine/engine_test.ts (Deno), run
// against the generated Convex module to prove the copy is faithful.
const presets: Record<string, Record<string, unknown>> = {
  international: { board_size: 10, backward_capture: true, flying_king: true, majority_capture: true },
  brazilian: { board_size: 8, backward_capture: true, flying_king: true, majority_capture: true },
  american: { board_size: 8, backward_capture: false, flying_king: false, majority_capture: false },
};

type Vector = {
  preset: string;
  seed: number;
  ply: number;
  board: number[];
  side: string;
  legal_move_keys: string[];
  result?: string;
};

const vectors = vectorFile.vectors as Vector[];

describe("convex engine module", () => {
  test("matches Dart legal-move sets on every vector", () => {
    let checked = 0;
    for (const vector of vectors) {
      if (!vector.legal_move_keys.length && vector.result) continue;
      const state = {
        board: [...vector.board],
        side: vector.side,
        no_progress_plies: 0,
        endgame_countdown: -1,
        result: "ongoing",
        result_reason: "none",
        history: [],
        ply: vector.ply,
      };
      const keys = Engine.legalMoves(state, presets[vector.preset])
        .map((m: unknown) => Engine.moveKey(m))
        .sort();
      expect(keys, `${vector.preset} seed ${vector.seed} ply ${vector.ply}`).toEqual(vector.legal_move_keys);
      checked++;
    }
    expect(checked).toBeGreaterThan(100);
  });

  test("dispatch: initial_state, apply_move, illegal move, replay", () => {
    const config = presets.international;
    const state = checkersEngine("initial_state", { config });
    expect(state.side).toBe("white");
    const [first] = checkersEngine("legal_moves", { state, config }).moves;
    const applied = checkersEngine("apply_move", { state: structuredClone(state), config, move: first });
    expect(applied.error).toBeUndefined();
    expect(applied.state.side).toBe("black");
    expect(checkersEngine("apply_move", { state, config, move: { from: 0, path: [1], captured: [] } }).error).toBe(
      "illegal_move",
    );
    const replayed = checkersEngine("replay", { config, moves: [first] });
    expect(replayed.state.board).toEqual(applied.state.board);
  });
});
