#!/usr/bin/env bash
# Regenerates supabase/migrations/0002_engine.sql from the canonical JS
# engine source. Run after any change to supabase/engine/engine.js, then
# apply with scripts/db_apply.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=supabase/migrations/0002_engine.sql
{
  echo "-- GENERATED FILE — do not edit. Source: supabase/engine/engine.js"
  echo "-- Rebuild with scripts/build_engine_sql.sh"
  echo "create extension if not exists plv8;"
  echo
  echo "create or replace function public.checkers_engine(action text, payload jsonb)"
  echo "returns jsonb"
  echo "language plv8"
  echo "immutable"
  echo "as \$engine_js\$"
  cat supabase/engine/engine.js
  cat <<'DISPATCH'

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
      // Rebuild a state from scratch (PC-game undo support).
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
DISPATCH
  echo "\$engine_js\$;"
  echo
  echo "revoke all on function public.checkers_engine(text, jsonb) from public;"
  echo "revoke all on function public.checkers_engine(text, jsonb) from anon;"
  echo "revoke all on function public.checkers_engine(text, jsonb) from authenticated;"
} > "$OUT"
echo "wrote $OUT"
