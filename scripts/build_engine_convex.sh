#!/usr/bin/env bash
# Regenerates backend/convex/lib/engine.js (an ES module for Convex) from the
# canonical JS engine source. Run after any change to supabase/engine/engine.js.
# The dispatch mirrors checkers_engine() in scripts/build_engine_sql.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=backend/convex/lib/engine.js
{
  echo "// GENERATED FILE — do not edit. Source: supabase/engine/engine.js"
  echo "// Rebuild with scripts/build_engine_convex.sh"
  echo "/* eslint-disable */"
  cat supabase/engine/engine.js
  cat <<'DISPATCH'

export { CheckersEngineJS };

/**
 * Same contract as the plv8 `checkers_engine(action, payload)` function.
 * `apply_move` mutates `payload.state` in place and returns it.
 */
export function checkersEngine(action, payload) {
  var E = CheckersEngineJS;
  var config = payload.config;
  switch (action) {
    case 'initial_state':
      return E.initialState(config);
    case 'legal_moves':
      return { moves: E.legalMoves(payload.state, config) };
    case 'apply_move': {
      var state = payload.state;
      var canonical = E.findLegalMove(state, config, payload.move);
      if (!canonical) {
        return { error: 'illegal_move' };
      }
      E.applyMove(state, canonical, config);
      return { state: state, move: canonical };
    }
    case 'replay': {
      var replayState = E.initialState(config);
      var moves = payload.moves || [];
      for (var i = 0; i < moves.length; i++) {
        var legal = E.findLegalMove(replayState, config, moves[i]);
        if (!legal) {
          return { error: 'illegal_replay_move', at: i };
        }
        E.applyMove(replayState, legal, config);
      }
      return { state: replayState };
    }
    default:
      return { error: 'unknown_action' };
  }
}
DISPATCH
} > "$OUT"

# Plain .d.ts so TypeScript callers get a typed surface.
cat > backend/convex/lib/engine.d.ts <<'DTS'
// GENERATED FILE — do not edit. Rebuild with scripts/build_engine_convex.sh
export type EngineAction = 'initial_state' | 'legal_moves' | 'apply_move' | 'replay';
export declare const CheckersEngineJS: any;
export declare function checkersEngine(action: EngineAction, payload: any): any;
DTS
echo "wrote $OUT"
