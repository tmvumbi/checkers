// Deno test: runs the JS engine against the Dart-generated vector suite.
//   deno test --allow-read supabase/engine/engine_test.ts
// Regenerate vectors with: dart run tool/generate_vectors.dart
import { assertEquals } from 'jsr:@std/assert';

// Load the plv8-compatible engine source into this scope.
const source = await Deno.readTextFile(
  new URL('./engine.js', import.meta.url),
);
// deno-lint-ignore no-eval
eval(source);
// deno-lint-ignore no-explicit-any
const Engine = (globalThis as any).CheckersEngineJS;

const presets: Record<string, Record<string, unknown>> = {
  international: {
    board_size: 10,
    backward_capture: true,
    flying_king: true,
    majority_capture: true,
  },
  brazilian: {
    board_size: 8,
    backward_capture: true,
    flying_king: true,
    majority_capture: true,
  },
  american: {
    board_size: 8,
    backward_capture: false,
    flying_king: false,
    majority_capture: false,
  },
};

interface Vector {
  preset: string;
  seed: number;
  ply: number;
  board: number[];
  side: string;
  legal_move_keys: string[];
  result?: string;
  result_reason?: string;
}

const data = JSON.parse(
  await Deno.readTextFile(new URL('./test_vectors.json', import.meta.url)),
);
const vectors: Vector[] = data.vectors;

Deno.test('JS engine matches Dart legal-move sets on every vector', () => {
  let checked = 0;
  for (const vector of vectors) {
    if (!vector.legal_move_keys.length && vector.result) continue;
    const config = presets[vector.preset];
    const state = {
      board: [...vector.board],
      side: vector.side,
      no_progress_plies: 0,
      endgame_countdown: -1,
      result: 'ongoing',
      result_reason: 'none',
      history: [],
      ply: vector.ply,
    };
    const moves = Engine.legalMoves(state, config);
    const keys = moves.map((m: unknown) => Engine.moveKey(m)).sort();
    assertEquals(
      keys,
      vector.legal_move_keys,
      `mismatch at ${vector.preset} seed ${vector.seed} ply ${vector.ply}`,
    );
    checked++;
  }
  if (checked < 100) {
    throw new Error(`suspiciously few vectors checked: ${checked}`);
  }
});

Deno.test('full-game replay reaches the same result as Dart', () => {
  // Group terminal vectors and replay each seeded game through applyMove
  // by re-picking moves with the generator's deterministic formula.
  for (const presetName of Object.keys(presets)) {
    for (let seed = 1; seed <= 3; seed++) {
      const terminal = vectors.find(
        (v) => v.preset === presetName && v.seed === seed && v.result,
      );
      if (!terminal) continue;
      const config = presets[presetName];
      const state = Engine.initialState(config);
      let ply = 0;
      while (state.result === 'ongoing' && ply < 120) {
        const moves = Engine.legalMoves(state, config);
        const pick = (ply * seed * 7919 + seed * 31) % moves.length;
        Engine.applyMove(state, moves[pick], config);
        ply++;
      }
      assertEquals(
        { result: state.result, reason: state.result_reason, ply },
        {
          result: terminal.result,
          reason: terminal.result_reason,
          ply: terminal.ply,
        },
        `${presetName} seed ${seed}`,
      );
    }
  }
});
