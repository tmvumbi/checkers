-- GENERATED FILE — do not edit. Source: supabase/engine/engine.js
-- Rebuild with scripts/build_engine_sql.sh
create extension if not exists plv8;

create or replace function public.checkers_engine(action text, payload jsonb)
returns jsonb
language plv8
immutable
as $engine_js$
// Server-side checkers rules engine — the authoritative mirror of the Dart
// engine (lib/engine/). Runs inside Postgres via plv8 AND in Deno for the
// shared test-vector suite. Keep dependency-free and side-effect free.
//
// Board representation: array of N cells (N = playable squares), values:
//   0 empty, 1 white man, 2 white king, 3 black man, 4 black king.
// Squares are 0-based FMJD indices (row-major from Black's back row).
// Position repetition uses exact position strings, not hashes (plv8 numbers
// are doubles; 63-bit Zobrist keys don't fit).

'use strict';

var CheckersEngineJS = (function () {
  var EMPTY = 0, WM = 1, WK = 2, BM = 3, BK = 4;
  var WHITE = 'white', BLACK = 'black';

  var geometryCache = {};

  function geometry(boardSize) {
    if (geometryCache[boardSize]) return geometryCache[boardSize];
    var perRow = boardSize / 2;
    var count = boardSize * perRow;
    function indexOf(row, col) {
      if (row < 0 || row >= boardSize || col < 0 || col >= boardSize) return -1;
      if ((row + col) % 2 === 0) return -1;
      return row * perRow + (col >> 1);
    }
    function rowOf(s) { return Math.floor(s / perRow); }
    function colOf(s) {
      var row = rowOf(s), pos = s % perRow;
      return row % 2 === 0 ? pos * 2 + 1 : pos * 2;
    }
    var neighbors = [[], [], [], []]; // NW, NE, SW, SE
    for (var s = 0; s < count; s++) {
      var r = rowOf(s), c = colOf(s);
      neighbors[0][s] = indexOf(r - 1, c - 1);
      neighbors[1][s] = indexOf(r - 1, c + 1);
      neighbors[2][s] = indexOf(r + 1, c - 1);
      neighbors[3][s] = indexOf(r + 1, c + 1);
    }
    var g = {
      boardSize: boardSize, perRow: perRow, count: count,
      neighbors: neighbors, rowOf: rowOf, colOf: colOf,
    };
    geometryCache[boardSize] = g;
    return g;
  }

  function initialBoard(config) {
    var g = geometry(config.board_size);
    var men = g.perRow * (config.board_size / 2 - 1);
    var board = [];
    for (var s = 0; s < g.count; s++) board[s] = EMPTY;
    for (var b = 0; b < men; b++) board[b] = BM;
    for (var w = g.count - men; w < g.count; w++) board[w] = WM;
    return board;
  }

  function isWhite(v) { return v === WM || v === WK; }
  function isBlack(v) { return v === BM || v === BK; }
  function isKing(v) { return v === WK || v === BK; }
  function colorOf(v) { return isWhite(v) ? WHITE : (isBlack(v) ? BLACK : null); }

  function positionKey(board, side) {
    return board.join('') + '|' + side;
  }

  function usesFmjdDrawRules(config) { return !!config.majority_capture; }

  // --- Move generation -------------------------------------------------

  function manCaptureDirs(config, color) {
    if (config.backward_capture) return [0, 1, 2, 3];
    return color === WHITE ? [0, 1] : [2, 3];
  }

  function generateCaptures(board, side, config) {
    var g = geometry(config.board_size);
    var out = [];

    function record(origin, path, captured) {
      out.push({ from: origin, path: path.slice(), captured: captured.slice() });
    }

    function manDfs(color, origin, current, captured, path) {
      var dirs = manCaptureDirs(config, color);
      var extended = false;
      for (var d = 0; d < dirs.length; d++) {
        var dir = dirs[d];
        var over = g.neighbors[dir][current];
        if (over === -1) continue;
        var overVal = board[over];
        if (overVal === EMPTY) continue;
        if (colorOf(overVal) !== (color === WHITE ? BLACK : WHITE)) continue;
        if (captured.indexOf(over) !== -1) continue;
        var landing = g.neighbors[dir][over];
        if (landing === -1) continue;
        // The origin square is empty mid-sequence and may be landed on.
        if (landing !== origin && board[landing] !== EMPTY) continue;
        extended = true;
        captured.push(over); path.push(landing);
        manDfs(color, origin, landing, captured, path);
        captured.pop(); path.pop();
      }
      if (!extended && captured.length > 0) record(origin, path, captured);
    }

    function kingDfs(color, origin, current, captured, path) {
      // The mover's origin square is empty for the whole sequence; captured
      // pieces stay on the board as blockers (FMJD Art. 4.11).
      function effectiveEmpty(sq) {
        return sq === origin || board[sq] === EMPTY;
      }

      var extended = false;
      for (var dir = 0; dir < 4; dir++) {
        var over = g.neighbors[dir][current];
        if (config.flying_king) {
          while (over !== -1 && effectiveEmpty(over)) {
            over = g.neighbors[dir][over];
          }
        }
        if (over === -1 || effectiveEmpty(over)) continue;
        var overVal = board[over];
        if (colorOf(overVal) !== (color === WHITE ? BLACK : WHITE)) continue;
        if (captured.indexOf(over) !== -1) continue;
        var landing = g.neighbors[dir][over];
        while (landing !== -1 && effectiveEmpty(landing)) {
          extended = true;
          captured.push(over); path.push(landing);
          kingDfs(color, origin, landing, captured, path);
          captured.pop(); path.pop();
          if (!config.flying_king) break;
          landing = g.neighbors[dir][landing];
        }
      }
      if (!extended && captured.length > 0) record(origin, path, captured);
    }

    // NOTE on captured blockers: captured pieces are NOT removed from
    // `board` during the DFS, so they naturally keep blocking slides and
    // landings (FMJD Art. 4.11); re-jumps are prevented via the captured
    // list checks.
    for (var s = 0; s < g.count; s++) {
      var v = board[s];
      if (v === EMPTY || colorOf(v) !== side) continue;
      if (isKing(v)) kingDfs(side, s, s, [], []);
      else manDfs(side, s, s, [], []);
    }

    if (out.length === 0) return out;
    if (config.majority_capture) {
      var max = 0;
      for (var i = 0; i < out.length; i++) {
        if (out[i].captured.length > max) max = out[i].captured.length;
      }
      var majority = [];
      for (var j = 0; j < out.length; j++) {
        if (out[j].captured.length === max) majority.push(out[j]);
      }
      out = majority;
    }
    // Dedup by legal identity (from, to, captured-set).
    var seen = {}, deduped = [];
    for (var k = 0; k < out.length; k++) {
      var m = out[k];
      var key = moveKey(m);
      if (!seen[key]) { seen[key] = true; deduped.push(m); }
    }
    return deduped;
  }

  function moveKey(move) {
    var caps = move.captured.slice().sort(function (a, b) { return a - b; });
    return move.from + '>' + move.path[move.path.length - 1] + ':' + caps.join(',');
  }

  function generateQuiet(board, side, config) {
    var g = geometry(config.board_size);
    var out = [];
    var forward = side === WHITE ? [0, 1] : [2, 3];
    for (var s = 0; s < g.count; s++) {
      var v = board[s];
      if (v === EMPTY || colorOf(v) !== side) continue;
      if (isKing(v)) {
        for (var dir = 0; dir < 4; dir++) {
          var to = g.neighbors[dir][s];
          while (to !== -1 && board[to] === EMPTY) {
            out.push({ from: s, path: [to], captured: [] });
            if (!config.flying_king) break;
            to = g.neighbors[dir][to];
          }
        }
      } else {
        for (var f = 0; f < forward.length; f++) {
          var t = g.neighbors[forward[f]][s];
          if (t !== -1 && board[t] === EMPTY) {
            out.push({ from: s, path: [t], captured: [] });
          }
        }
      }
    }
    return out;
  }

  function legalMoves(state, config) {
    if (state.result !== 'ongoing') return [];
    var captures = generateCaptures(state.board, state.side, config);
    if (captures.length > 0) return annotatePromotion(captures, state, config);
    return annotatePromotion(
      generateQuiet(state.board, state.side, config), state, config);
  }

  function annotatePromotion(moves, state, config) {
    var g = geometry(config.board_size);
    for (var i = 0; i < moves.length; i++) {
      var m = moves[i];
      var v = state.board[m.from];
      var to = m.path[m.path.length - 1];
      m.promotes = !isKing(v) && (
        (colorOf(v) === WHITE && g.rowOf(to) === 0) ||
        (colorOf(v) === BLACK && g.rowOf(to) === config.board_size - 1)
      );
    }
    return moves;
  }

  // --- State transitions ----------------------------------------------

  function initialState(config) {
    var board = initialBoard(config);
    var state = {
      board: board,
      side: WHITE,
      no_progress_plies: 0,
      endgame_countdown: -1,
      result: 'ongoing',
      result_reason: 'none',
      history: [positionKey(board, WHITE)],
      ply: 0,
    };
    return state;
  }

  function applyMove(state, move, config) {
    var board = state.board;
    var v = board[move.from];
    var wasKing = isKing(v);
    var color = colorOf(v);
    var to = move.path[move.path.length - 1];

    board[move.from] = EMPTY;
    for (var i = 0; i < move.captured.length; i++) {
      board[move.captured[i]] = EMPTY;
    }
    var becomesKing = wasKing || !!move.promotes;
    board[to] = color === WHITE ? (becomesKing ? WK : WM) : (becomesKing ? BK : BM);

    state.side = color === WHITE ? BLACK : WHITE;
    state.ply += 1;
    if (move.captured.length > 0 || !wasKing) {
      state.no_progress_plies = 0;
    } else {
      state.no_progress_plies += 1;
    }
    state.history.push(positionKey(board, state.side));

    updateEndgameCountdown(state, config);
    evaluateResult(state, config);
    return state;
  }

  function countMaterial(board) {
    var wm = 0, wk = 0, bm = 0, bk = 0;
    for (var i = 0; i < board.length; i++) {
      if (board[i] === WM) wm++;
      else if (board[i] === WK) wk++;
      else if (board[i] === BM) bm++;
      else if (board[i] === BK) bk++;
    }
    return { wm: wm, wk: wk, bm: bm, bk: bk };
  }

  function isLone(men, kings) { return men === 0 && kings === 1; }

  function isFiveClass(m) {
    function strong(men, kings) {
      return kings >= 1 && men + kings <= 2 && men + kings >= 1;
    }
    return (isLone(m.bm, m.bk) && strong(m.wm, m.wk)) ||
           (isLone(m.wm, m.wk) && strong(m.bm, m.bk));
  }

  function isSixteenClass(m) {
    function strong(men, kings) { return kings >= 1 && men + kings === 3; }
    return (isLone(m.bm, m.bk) && strong(m.wm, m.wk)) ||
           (isLone(m.wm, m.wk) && strong(m.bm, m.bk));
  }

  function updateEndgameCountdown(state, config) {
    if (!usesFmjdDrawRules(config)) return;
    var m = countMaterial(state.board);
    if (isFiveClass(m)) {
      if (state.endgame_countdown < 0 || state.endgame_countdown > 10) {
        state.endgame_countdown = 10;
      } else {
        state.endgame_countdown -= 1;
      }
    } else if (isSixteenClass(m)) {
      if (state.endgame_countdown < 0) {
        state.endgame_countdown = 32;
      } else {
        state.endgame_countdown -= 1;
      }
    } else {
      state.endgame_countdown = -1;
    }
  }

  function evaluateResult(state, config) {
    var side = state.side;
    var m = countMaterial(state.board);
    var own = side === WHITE ? m.wm + m.wk : m.bm + m.bk;
    if (own === 0) {
      state.result = side === WHITE ? 'blackWin' : 'whiteWin';
      state.result_reason = 'noPieces';
      return;
    }
    var moves = generateCaptures(state.board, side, config);
    if (moves.length === 0) {
      moves = generateQuiet(state.board, side, config);
    }
    if (moves.length === 0) {
      state.result = side === WHITE ? 'blackWin' : 'whiteWin';
      state.result_reason = 'blocked';
      return;
    }

    var current = positionKey(state.board, side);
    var repetitions = 0;
    for (var i = 0; i < state.history.length; i++) {
      if (state.history[i] === current) repetitions++;
    }
    if (repetitions >= 3) {
      state.result = 'draw';
      state.result_reason = 'repetition';
      return;
    }

    if (usesFmjdDrawRules(config)) {
      if (state.no_progress_plies >= 50) {
        state.result = 'draw';
        state.result_reason = 'kingMoves25';
        return;
      }
      if (state.endgame_countdown === 0) {
        state.result = 'draw';
        state.result_reason = isFiveClass(countMaterial(state.board))
          ? 'endgame5' : 'endgame16';
        return;
      }
    } else if (state.no_progress_plies >= 80) {
      state.result = 'draw';
      state.result_reason = 'noProgress40';
      return;
    }
  }

  /// Validates a client-submitted move against the current legal set.
  /// Returns the matching canonical move or null.
  function findLegalMove(state, config, submitted) {
    var moves = legalMoves(state, config);
    var to = submitted.path && submitted.path.length
      ? submitted.path[submitted.path.length - 1]
      : submitted.to;
    var caps = (submitted.captured || []).slice().sort(function (a, b) { return a - b; });
    for (var i = 0; i < moves.length; i++) {
      var m = moves[i];
      var mto = m.path[m.path.length - 1];
      if (m.from !== submitted.from || mto !== to) continue;
      var mcaps = m.captured.slice().sort(function (a, b) { return a - b; });
      if (caps.length && mcaps.join(',') !== caps.join(',')) continue;
      return m;
    }
    return null;
  }

  return {
    geometry: geometry,
    initialState: initialState,
    legalMoves: legalMoves,
    applyMove: applyMove,
    findLegalMove: findLegalMove,
    moveKey: moveKey,
    countMaterial: countMaterial,
  };
})();

// Deno/Node export without breaking plv8 (plv8 has no module system).
if (typeof globalThis !== 'undefined') {
  globalThis.CheckersEngineJS = CheckersEngineJS;
}

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
$engine_js$;

revoke all on function public.checkers_engine(text, jsonb) from public;
revoke all on function public.checkers_engine(text, jsonb) from anon;
revoke all on function public.checkers_engine(text, jsonb) from authenticated;
