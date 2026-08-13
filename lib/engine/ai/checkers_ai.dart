import '../board_geometry.dart';
import '../checkers_engine.dart';
import '../move.dart';
import 'ai_config.dart';

class _TtEntry {
  _TtEntry(this.depth, this.score, this.flag);

  final int depth;
  final int score;
  final int flag; // 0 exact, 1 lower bound, 2 upper bound.
}

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

/// Negamax + alpha-beta with iterative deepening, a transposition table and
/// forced-capture quiescence (PRD §7.3). Synchronous — run it inside an
/// isolate from UI code.
class CheckersAi {
  CheckersAi(this.engine, this.config);

  final CheckersEngine engine;
  final AiConfig config;

  final Map<int, _TtEntry> _table = {};
  int _nodes = 0;
  int _deadline = 0;
  bool _aborted = false;

  static const int _win = 1 << 20;

  /// Deterministic per-position pseudo-randomness: hash-mixed so results are
  /// reproducible and the transposition table stays consistent.
  int _mix(int seed) {
    var x = seed ^ 0x9E3779B97F4A7C15;
    x = (x ^ (x >>> 30)) * 0xBF58476D1CE4E5B9;
    x = (x ^ (x >>> 27)) * 0x94D049BB133111EB;
    return (x ^ (x >>> 31)) & 0x7FFFFFFFFFFFFFFF;
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
    _table.clear();

    // Iterative deepening over root moves, keeping per-move scores so the
    // difficulty layer can pick among the top N.
    var rootScores = <MapEntry<Move, int>>[
      for (final move in legal) MapEntry(move, 0),
    ];
    var completedDepth = 0;

    for (var depth = 1; depth <= config.maxDepth; depth++) {
      final iterationScores = <MapEntry<Move, int>>[];
      var alpha = -_win * 2;
      // Search in the previous iteration's order for better pruning.
      for (final entry in rootScores) {
        final move = entry.key;
        engine.applyMove(move);
        final score = -_negamax(depth - 1, -_win * 2, -alpha);
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
      // Stop early on a proven win.
      if (rootScores.first.value >= _win - 100) {
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

  int _negamax(int depth, int alpha, int beta) {
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
        return -_win + (_nodes & 63);
    }

    final moves = engine.legalMoves();
    final isCapturePosition = moves.isNotEmpty && moves.first.isCapture;

    // Quiescence: never evaluate a position with pending forced captures.
    if (depth <= 0 && !isCapturePosition) {
      return _evaluate();
    }

    final originalAlpha = alpha;
    final entry = _table[engine.hash];
    if (entry != null && entry.depth >= depth) {
      if (entry.flag == 0) {
        return entry.score;
      }
      if (entry.flag == 1 && entry.score > alpha) {
        alpha = entry.score;
      } else if (entry.flag == 2 && entry.score < beta) {
        beta = entry.score;
      }
      if (alpha >= beta) {
        return entry.score;
      }
    }

    // Forced-move extension keeps the horizon honest in forcing lines.
    final nextDepth = moves.length == 1 ? depth : depth - 1;

    var best = -_win * 2;
    for (final move in moves) {
      engine.applyMove(move);
      final score = -_negamax(nextDepth, -beta, -alpha);
      engine.undoMove();
      if (_aborted) {
        return 0;
      }
      if (score > best) {
        best = score;
      }
      if (best > alpha) {
        alpha = best;
      }
      if (alpha >= beta) {
        break;
      }
    }

    final flag = best <= originalAlpha ? 2 : (best >= beta ? 1 : 0);
    if (_table.length < 1 << 18) {
      _table[engine.hash] = _TtEntry(depth, best, flag);
    }
    return best;
  }

  // -------------------------------------------------------------------
  // Evaluation (from the side to move's perspective, centi-men units)
  // -------------------------------------------------------------------

  int _evaluate() {
    final config = engine.config;
    final geometry = engine.geometry;
    final kingValue = config.flyingKing ? 300 : 140;
    final size = config.boardSize;

    var score = 0;
    for (var square = 0; square < config.squareCount; square++) {
      final color = engine.colorAt(square);
      if (color == null) {
        continue;
      }
      final isKing = engine.isKingAt(square);
      var value = isKing ? kingValue : 100;

      if (!isKing) {
        final row = geometry.rowOf(square);
        // Advancement: rows toward promotion are worth a nudge.
        final advance = color == PieceColor.white ? (size - 1 - row) : row;
        value += advance * 3;
        // Back-row guard bonus while the game is young.
        final onBackRow = color == PieceColor.white
            ? row == size - 1
            : row == 0;
        if (onBackRow) {
          value += 8;
        }
      }
      // Edge pieces have half the capture cover.
      final col = geometry.colOf(square);
      if (col == 0 || col == size - 1) {
        value -= 6;
      }

      score += color == engine.sideToMove ? value : -value;
    }

    if (this.config.noiseCentiMen > 0) {
      final noise =
          (_mix(engine.hash) % (2 * this.config.noiseCentiMen + 1)) -
          this.config.noiseCentiMen;
      score += noise;
    }
    return score;
  }
}

// Re-exported so isolate entry points only need this import.
typedef AiBoardGeometry = BoardGeometry;
