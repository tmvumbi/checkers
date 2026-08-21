import 'dart:typed_data';

import '../board_geometry.dart';
import '../checkers_engine.dart';
import '../move.dart';
import 'ai_config.dart';
import 'evaluator.dart';

class AiMoveChoice {
  const AiMoveChoice({
    required this.move,
    required this.score,
    required this.depth,
    required this.nodes,
  });

  final Move move;
  final int score;
  final int depth;
  final int nodes;
}

/// Negamax + alpha-beta with iterative deepening, a fixed-size shared
/// transposition table, PVS, aspiration windows, late-move reductions and
/// forced-capture quiescence (PRD §7.3). Synchronous — run it inside an
/// isolate from UI code.
///
/// The instance is designed to live across moves: the transposition table
/// ages by generation instead of being cleared, and [engine]/[config] may
/// be swapped between searches (the persistent AI isolate does both).
class CheckersAi {
  CheckersAi(this.engine, this.config);

  CheckersEngine engine;
  AiConfig config;

  // ---- transposition table (fixed typed arrays, ~8 MB) ----
  static const int _ttBits = 19;
  static const int _ttMask = (1 << _ttBits) - 1;
  final Int64List _ttKeys = Int64List(1 << _ttBits);
  final Int64List _ttData = Int64List(1 << _ttBits);
  int _generation = 0;

  // data layout: score+_scoreOffset (22b) | depth<<22 (7b) | flag<<29 (2b)
  //            | bestId<<31 (12b) | generation<<43 (8b)
  static const int _scoreOffset = 1 << 21;

  // ---- move ordering state ----
  static const int _maxPly = 96;
  final Int32List _killers = Int32List(2 * _maxPly);
  final Int32List _history = Int32List(1 << 12);
  final Int32List _counterMoves = Int32List(1 << 12);

  // Scratch: previous move id per ply for the countermove heuristic.
  final Int32List _prevMoveId = Int32List(_maxPly + 2);

  int _nodes = 0;
  int _deadline = 0;
  bool _aborted = false;

  Evaluator? _evaluator;

  static const int _win = 1 << 20;
  static const int _mateBound = _win - 2 * _maxPly;
  static const int _infinity = _win * 2;

  static int _moveId(Move move) => (move.from << 6) | move.to;

  /// Deterministic per-position pseudo-randomness: hash-mixed so results are
  /// reproducible and the transposition table stays consistent.
  int _mix(int seed) {
    var x = seed ^ 0x9E3779B97F4A7C15;
    x = (x ^ (x >>> 30)) * 0xBF58476D1CE4E5B9;
    x = (x ^ (x >>> 27)) * 0x94D049BB133111EB;
    return (x ^ (x >>> 31)) & 0x7FFFFFFFFFFFFFFF;
  }

  /// Prepares ordering state for a fresh search while keeping the warm
  /// transposition table (aged by generation).
  void _newSearch() {
    _generation = (_generation + 1) & 0xFF;
    _killers.fillRange(0, _killers.length, 0);
    for (var i = 0; i < _history.length; i++) {
      _history[i] >>= 1;
    }
    _prevMoveId.fillRange(0, _prevMoveId.length, 0);
  }

  /// Drops all cross-move search state; call when the position context
  /// changes entirely (new game, different rules).
  void resetTables() {
    _ttKeys.fillRange(0, _ttKeys.length, 0);
    _ttData.fillRange(0, _ttData.length, 0);
    _history.fillRange(0, _history.length, 0);
    _counterMoves.fillRange(0, _counterMoves.length, 0);
  }

  AiMoveChoice chooseMove({int? nowMs}) {
    final legal = engine.legalMoves();
    assert(legal.isNotEmpty, 'no legal moves');
    if (legal.length == 1) {
      return AiMoveChoice(move: legal.first, score: 0, depth: 0, nodes: 1);
    }

    final start = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _deadline = start + config.budgetMs;
    _aborted = false;
    _nodes = 0;
    _newSearch();
    _evaluator = config.search.evalVersion >= 2
        ? Evaluator.forConfig(engine.geometry, flying: engine.config.flyingKing)
        : null;
    engine.searchMode = true;
    try {
      return config.level == AiLevel.hard
          ? _searchHard(legal, start)
          : _searchGraded(legal);
    } finally {
      engine.searchMode = false;
    }
  }

  // -------------------------------------------------------------------
  // Root search, full-strength profile: PVS + aspiration windows.
  // -------------------------------------------------------------------

  AiMoveChoice _searchHard(List<Move> legal, int startMs) {
    final options = config.search;
    var order = List.of(legal);
    var bestMove = order.first;
    var bestScore = 0;
    var completedDepth = 0;
    var stableIterations = 0;

    for (var depth = 1; depth <= config.maxDepth; depth++) {
      var alpha = -_infinity;
      var beta = _infinity;
      var window = 30;
      if (options.useAspiration && completedDepth >= 4 &&
          bestScore.abs() < _mateBound) {
        alpha = bestScore - window;
        beta = bestScore + window;
      }

      var iterationBest = -_infinity;
      Move? iterationMove;
      while (true) {
        iterationBest = -_infinity;
        iterationMove = null;
        var raisedAlpha = alpha;
        for (var i = 0; i < order.length; i++) {
          final move = order[i];
          engine.applyMove(move);
          _prevMoveId[1] = _moveId(move);
          int score;
          if (i == 0 || !options.usePvs) {
            score = -_negamax(depth - 1, 1, -beta, -raisedAlpha);
          } else {
            score = -_negamax(depth - 1, 1, -raisedAlpha - 1, -raisedAlpha);
            if (!_aborted && score > raisedAlpha && score < beta) {
              score = -_negamax(depth - 1, 1, -beta, -raisedAlpha);
            }
          }
          engine.undoMove();
          if (_aborted) {
            break;
          }
          if (score > iterationBest) {
            iterationBest = score;
            iterationMove = move;
          }
          if (score > raisedAlpha) {
            raisedAlpha = score;
          }
        }
        if (_aborted) {
          break;
        }
        // Aspiration window management.
        if (iterationBest <= alpha && alpha > -_infinity) {
          window *= 4;
          alpha = iterationBest - window;
          continue;
        }
        if (iterationBest >= beta && beta < _infinity) {
          window *= 4;
          beta = iterationBest + window;
          continue;
        }
        break;
      }
      if (_aborted) {
        break;
      }

      final previousBest = bestMove;
      bestMove = iterationMove ?? bestMove;
      bestScore = iterationBest;
      completedDepth = depth;

      // Search the new best move first next iteration.
      order
        ..remove(bestMove)
        ..insert(0, bestMove);

      if (bestScore >= _win - _maxPly) {
        break; // proven win
      }
      if (options.useEarlyStop) {
        stableIterations = bestMove == previousBest ? stableIterations + 1 : 0;
        if (stableIterations >= 4 && depth >= 12) {
          final elapsed = DateTime.now().millisecondsSinceEpoch - startMs;
          if (elapsed * 100 > config.budgetMs * 55) {
            break;
          }
        }
      }
    }

    final chosen = _maybeVariety(legal, bestMove, completedDepth) ?? bestMove;
    return AiMoveChoice(
      move: chosen,
      score: bestScore,
      depth: completedDepth,
      nodes: _nodes,
    );
  }

  /// Opening variety: with a non-zero seed, re-score the closest root
  /// alternatives with full windows at a reduced depth (cheap on a warm
  /// table) and pick randomly among near-equal moves.
  Move? _maybeVariety(List<Move> legal, Move best, int completedDepth) {
    if (config.varietySeed == 0 ||
        engine.moveHistory.length >= 6 ||
        legal.length < 2 ||
        completedDepth < 6) {
      return null;
    }
    final depth = completedDepth - 3;
    _deadline += 500; // small extra allowance; warm TT makes this fast
    final scored = <(Move, int)>[];
    for (final move in legal.take(6)) {
      engine.applyMove(move);
      _prevMoveId[1] = _moveId(move);
      final score = -_negamax(depth - 1, 1, -_infinity, _infinity);
      engine.undoMove();
      if (_aborted) {
        return null;
      }
      scored.add((move, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final top = scored.first.$2;
    final eligible = [
      for (final entry in scored)
        if (top - entry.$2 <= 25) entry.$1,
    ];
    if (eligible.length < 2) {
      return null;
    }
    final pick =
        _mix(engine.hash ^ config.varietySeed) % eligible.length;
    return eligible[pick];
  }

  // -------------------------------------------------------------------
  // Root search, graded profiles: comparable root scores feed the
  // imperfection layer (bounded blunders, top-N randomness).
  // -------------------------------------------------------------------

  AiMoveChoice _searchGraded(List<Move> legal) {
    var rootScores = <MapEntry<Move, int>>[
      for (final move in legal) MapEntry(move, 0),
    ];
    var completedDepth = 0;

    for (var depth = 1; depth <= config.maxDepth; depth++) {
      final iterationScores = <MapEntry<Move, int>>[];
      var alpha = -_infinity;
      for (final entry in rootScores) {
        final move = entry.key;
        engine.applyMove(move);
        _prevMoveId[1] = _moveId(move);
        final score = -_negamax(depth - 1, 1, -_infinity, -alpha);
        engine.undoMove();
        if (_aborted) {
          break;
        }
        iterationScores.add(MapEntry(move, score));
        if (score > alpha) {
          alpha = score;
        }
      }
      if (_aborted) {
        break;
      }
      iterationScores.sort((a, b) => b.value.compareTo(a.value));
      rootScores = iterationScores;
      completedDepth = depth;
      if (rootScores.first.value >= _win - _maxPly) {
        break;
      }
    }

    final chosen = _applyImperfection(rootScores);
    return AiMoveChoice(
      move: chosen,
      score: rootScores.firstWhere((e) => e.key == chosen).value,
      depth: completedDepth,
      nodes: _nodes,
    );
  }

  Move _applyImperfection(List<MapEntry<Move, int>> ranked) {
    if (config.level == AiLevel.hard || ranked.length == 1) {
      return ranked.first.key;
    }
    final roll = _mix(engine.hash) % 1000;

    // Bounded blunder: play the best move that loses at most ~1.2 men,
    // preferring the worst such move.
    if (roll < (config.blunderChance * 1000).round()) {
      final best = ranked.first.value;
      for (final entry in ranked.reversed) {
        if (best - entry.value <= 120) {
          return entry.key;
        }
      }
    }

    // Randomized pick among the top N within half a man of the best.
    final roll2 = _mix(engine.hash ^ 0xABCDEF) % 1000;
    if (roll2 < (config.pickSecondBestChance * 1000).round()) {
      final best = ranked.first.value;
      final eligible = [
        for (final entry in ranked.take(config.topN))
          if (best - entry.value <= 50) entry,
      ];
      if (eligible.length > 1) {
        return eligible[_mix(engine.hash ^ 0x1234567) % eligible.length].key;
      }
    }
    return ranked.first.key;
  }

  // -------------------------------------------------------------------
  // Inner search
  // -------------------------------------------------------------------

  int _negamax(int depth, int ply, int alphaIn, int betaIn) {
    var alpha = alphaIn;
    var beta = betaIn;
    _nodes++;
    if ((_nodes & 1023) == 0 &&
        DateTime.now().millisecondsSinceEpoch > _deadline) {
      _aborted = true;
      return 0;
    }

    switch (engine.result) {
      case GameResult.ongoing:
        break;
      case GameResult.draw:
        return 0;
      case GameResult.whiteWin:
      case GameResult.blackWin:
        // The side to move has lost (previous mover ended the game).
        return -_win + ply;
    }

    // Mate-distance pruning: no result here can beat an already-found
    // shorter mate.
    if (alpha < -_win + ply) {
      alpha = -_win + ply;
    }
    if (beta > _win - ply - 1) {
      beta = _win - ply - 1;
    }
    if (alpha >= beta) {
      return alpha;
    }

    final moves = engine.legalMoves();
    if (moves.isEmpty) {
      // Blocked: the side to move loses (search-mode replaces the engine's
      // own blocked detection).
      return -_win + ply;
    }
    final isCapturePosition = moves.first.isCapture;

    // Quiescence: never evaluate a position with pending forced captures.
    if (depth <= 0 && !isCapturePosition) {
      return _evaluate();
    }

    final originalAlpha = alpha;

    // ---- transposition table probe ----
    final hash = engine.hash;
    final index = hash & _ttMask;
    var ttMoveId = 0;
    final storedKey = _ttKeys[index];
    if (storedKey == hash) {
      final data = _ttData[index];
      final entryDepth = (data >> 22) & 0x7F;
      ttMoveId = (data >> 31) & 0xFFF;
      if (entryDepth >= depth) {
        var score = (data & 0x3FFFFF) - _scoreOffset;
        // Mate scores are stored node-relative; rebase to this ply.
        if (score >= _mateBound) {
          score -= ply;
        } else if (score <= -_mateBound) {
          score += ply;
        }
        final flag = (data >> 29) & 0x3;
        if (flag == 0) {
          return score;
        }
        if (flag == 1 && score > alpha) {
          alpha = score;
        } else if (flag == 2 && score < beta) {
          beta = score;
        }
        if (alpha >= beta) {
          return score;
        }
      }
    }

    final options = config.search;

    // ---- move ordering ----
    if (moves.length > 1) {
      _orderMoves(moves, ply, ttMoveId, isCapturePosition, engine.kingsBB);
    }

    // Forced-move extension keeps the horizon honest in forcing lines.
    final extended = moves.length == 1;
    final nextDepth = extended ? depth : depth - 1;

    final counterIndex =
        options.useCounterMoves ? _prevMoveId[ply] : 0;
    final allowLmr = options.useLmr &&
        !isCapturePosition &&
        depth >= 3 &&
        !extended;

    var best = -_infinity;
    var bestId = 0;
    for (var i = 0; i < moves.length; i++) {
      final move = moves[i];
      final moveId = _moveId(move);
      engine.applyMove(move);
      if (ply + 1 < _prevMoveId.length) {
        _prevMoveId[ply + 1] = moveId;
      }

      int score;
      if (i == 0 || !options.usePvs) {
        score = -_negamax(nextDepth, ply + 1, -beta, -alpha);
      } else {
        var reduction = 0;
        if (allowLmr &&
            i >= 3 &&
            !move.promotes &&
            moveId != ttMoveId &&
            moveId != _killers[2 * ply] &&
            moveId != _killers[2 * ply + 1]) {
          reduction = (i >= 8 && depth >= 6) ? 2 : 1;
        }
        score = -_negamax(nextDepth - reduction, ply + 1, -alpha - 1, -alpha);
        if (!_aborted && score > alpha && reduction > 0) {
          score = -_negamax(nextDepth, ply + 1, -alpha - 1, -alpha);
        }
        if (!_aborted && score > alpha && score < beta) {
          score = -_negamax(nextDepth, ply + 1, -beta, -alpha);
        }
      }
      engine.undoMove();
      if (_aborted) {
        return 0;
      }
      if (score > best) {
        best = score;
        bestId = moveId;
      }
      if (best > alpha) {
        alpha = best;
      }
      if (alpha >= beta) {
        if (!move.isCapture) {
          if (_killers[2 * ply] != moveId) {
            _killers[2 * ply + 1] = _killers[2 * ply];
            _killers[2 * ply] = moveId;
          }
          _history[moveId] += depth * depth;
          if (_history[moveId] > 1 << 24) {
            for (var j = 0; j < _history.length; j++) {
              _history[j] >>= 1;
            }
          }
          if (counterIndex != 0) {
            _counterMoves[counterIndex] = moveId;
          }
        }
        break;
      }
    }

    // ---- transposition table store ----
    final flag = best <= originalAlpha ? 2 : (best >= beta ? 1 : 0);
    var storedScore = best;
    if (storedScore >= _mateBound) {
      storedScore += ply;
      if (storedScore >= _win) {
        storedScore = _win - 1;
      }
    } else if (storedScore <= -_mateBound) {
      storedScore -= ply;
      if (storedScore <= -_win) {
        storedScore = -_win + 1;
      }
    }
    final storedDepth = depth < 0 ? 0 : (depth > 127 ? 127 : depth);
    final existing = _ttData[index];
    final existingGeneration = (existing >> 43) & 0xFF;
    final existingDepth = (existing >> 22) & 0x7F;
    if (storedKey == 0 ||
        storedKey == hash ||
        existingGeneration != _generation ||
        storedDepth >= existingDepth) {
      _ttKeys[index] = hash;
      _ttData[index] = (storedScore + _scoreOffset) |
          (storedDepth << 22) |
          (flag << 29) |
          (bestId << 31) |
          (_generation << 43);
    }
    return best;
  }

  void _orderMoves(
    List<Move> moves,
    int ply,
    int ttMoveId,
    bool isCapturePosition,
    int kingsBB,
  ) {
    final counter = config.search.useCounterMoves && _prevMoveId[ply] != 0
        ? _counterMoves[_prevMoveId[ply]]
        : 0;
    final killer0 = _killers[2 * ply];
    final killer1 = _killers[2 * ply + 1];

    // Insertion sort by descending rank — move lists are short.
    for (var i = 1; i < moves.length; i++) {
      final move = moves[i];
      final rank = _rankOf(
        move,
        ttMoveId,
        killer0,
        killer1,
        counter,
        isCapturePosition,
        kingsBB,
      );
      var j = i - 1;
      while (j >= 0 &&
          _rankOf(
                moves[j],
                ttMoveId,
                killer0,
                killer1,
                counter,
                isCapturePosition,
                kingsBB,
              ) <
              rank) {
        moves[j + 1] = moves[j];
        j--;
      }
      moves[j + 1] = move;
    }
  }

  int _rankOf(
    Move move,
    int ttMoveId,
    int killer0,
    int killer1,
    int counter,
    bool isCapturePosition,
    int kingsBB,
  ) {
    final moveId = _moveId(move);
    if (moveId == ttMoveId) {
      return 1 << 30;
    }
    if (isCapturePosition) {
      // Bigger hauls first; captured kings outrank captured men.
      var rank = move.captured.length << 20;
      rank += _popCount(move.capturedMask & kingsBB) << 16;
      if (move.promotes) {
        rank += 1 << 15;
      }
      return rank;
    }
    if (moveId == killer0) {
      return (1 << 28) + 1;
    }
    if (moveId == killer1) {
      return 1 << 28;
    }
    if (moveId == counter) {
      return 1 << 27;
    }
    return _history[moveId];
  }

  static int _popCount(int mask) {
    var count = 0;
    var m = mask;
    while (m != 0) {
      m &= m - 1;
      count++;
    }
    return count;
  }

  // -------------------------------------------------------------------
  // Evaluation (from the side to move's perspective, centi-men units)
  // -------------------------------------------------------------------

  int _evaluate() {
    final evaluator = _evaluator;
    var score = evaluator != null ? evaluator.evaluate(engine) : _evaluateV1();

    if (config.noiseCentiMen > 0) {
      final noise =
          (_mix(engine.hash) % (2 * config.noiseCentiMen + 1)) -
          config.noiseCentiMen;
      score += noise;
    }
    return score;
  }

  int _evaluateV1() {
    final rules = engine.config;
    final geometry = engine.geometry;
    final kingValue = rules.flyingKing ? 300 : 140;
    final size = rules.boardSize;

    var score = 0;
    for (var square = 0; square < rules.squareCount; square++) {
      final color = engine.colorAt(square);
      if (color == null) {
        continue;
      }
      final isKing = engine.isKingAt(square);
      var value = isKing ? kingValue : 100;

      if (!isKing) {
        final row = geometry.rowOf(square);
        final advance = color == PieceColor.white ? (size - 1 - row) : row;
        value += advance * 3;
        final onBackRow = color == PieceColor.white
            ? row == size - 1
            : row == 0;
        if (onBackRow) {
          value += 8;
        }
      }
      final col = geometry.colOf(square);
      if (col == 0 || col == size - 1) {
        value -= 6;
      }

      score += color == engine.sideToMove ? value : -value;
    }
    return score;
  }
}

// Re-exported so isolate entry points only need this import.
typedef AiBoardGeometry = BoardGeometry;
