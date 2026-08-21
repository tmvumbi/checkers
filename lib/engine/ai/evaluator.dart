import 'dart:typed_data';

import '../board_geometry.dart';
import '../checkers_engine.dart';
import 'eval_params.dart';

/// Phase-tapered positional evaluation (v2). Returns centi-men from the
/// side to move's perspective.
///
/// Per board size it precomputes man piece-square tables (opening and
/// endgame, white view — black mirrors), wing masks, and promotion-cone
/// masks for runaway detection; instances are cached per (size, flying).
class Evaluator {
  Evaluator._(this.geometry, this.flyingKing) {
    _build();
  }

  static final Map<int, Evaluator> _cache = {};

  factory Evaluator.forConfig(BoardGeometry geometry, {required bool flying}) {
    final key = geometry.boardSize * 2 + (flying ? 1 : 0);
    return _cache.putIfAbsent(key, () => Evaluator._(geometry, flying));
  }

  final BoardGeometry geometry;
  final bool flyingKing;

  late final Int32List _manOpen; // white view
  late final Int32List _manEnd;
  late final Int32List _mirror; // 180° square mirror
  late final Int64List _whiteCone; // empty-cone masks toward promotion
  late final Int64List _blackCone;
  late final int _leftWingMask;
  late final int _startTotal;

  void _build() {
    final size = geometry.boardSize;
    final count = geometry.squareCount;
    _manOpen = Int32List(count);
    _manEnd = Int32List(count);
    _mirror = Int32List(count);
    _whiteCone = Int64List(count);
    _blackCone = Int64List(count);
    // Starting piece total: (size/2 - 1) rows of men per side.
    _startTotal = 2 * (size ~/ 2 - 1) * (size ~/ 2);

    var leftMask = 0;
    for (var square = 0; square < count; square++) {
      _mirror[square] = count - 1 - square;
      final row = geometry.rowOf(square);
      final col = geometry.colOf(square);
      final advance = size - 1 - row; // white advancement
      final isEdge = col == 0 || col == size - 1;
      final centerDistance = ((2 * col - (size - 1)).abs() - 1) ~/ 2;
      final centerScale = // 2 at dead center columns, 0 near the edges
          centerDistance <= 1 ? 2 : (centerDistance <= 2 ? 1 : 0);
      final nearPromotion = advance >= size - 3 && advance < size - 1;

      var open = advance * EvalParams.advanceOpen +
          centerScale * EvalParams.centerOpen ~/ 2;
      var end = advance * EvalParams.advanceEnd +
          centerScale * EvalParams.centerEnd ~/ 2;
      if (row == size - 1) {
        open += EvalParams.backRowOpen;
        end += EvalParams.backRowEnd;
      }
      if (isEdge) {
        open += EvalParams.edgeOpen;
        end += EvalParams.edgeEnd;
      }
      if (nearPromotion) {
        open += EvalParams.nearPromotionOpen;
        end += EvalParams.nearPromotionEnd;
      }
      _manOpen[square] = open;
      _manEnd[square] = end;

      if (col < size ~/ 2) {
        leftMask |= 1 << square;
      }

      // Promotion cones: every square reachable by forward diagonal steps.
      _whiteCone[square] = _cone(square, toWhitePromotion: true);
      _blackCone[square] = _cone(square, toWhitePromotion: false);
    }
    _leftWingMask = leftMask;
  }

  int _cone(int from, {required bool toWhitePromotion}) {
    var mask = 0;
    var frontier = 1 << from;
    final dirs = toWhitePromotion
        ? const [BoardGeometry.northWest, BoardGeometry.northEast]
        : const [BoardGeometry.southWest, BoardGeometry.southEast];
    while (frontier != 0) {
      var next = 0;
      var bits = frontier;
      while (bits != 0) {
        final square = (bits & -bits).bitLength - 1;
        bits &= bits - 1;
        for (final dir in dirs) {
          final neighbor = geometry.neighbors[dir][square];
          if (neighbor != -1) {
            next |= 1 << neighbor;
          }
        }
      }
      next &= ~mask;
      mask |= next;
      frontier = next;
    }
    return mask;
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

  /// Score from the side to move's perspective.
  int evaluate(CheckersEngine engine) {
    final size = geometry.boardSize;
    final total =
        engine.whiteMen + engine.whiteKings + engine.blackMen + engine.blackKings;
    // 256 = full opening, 0 = bare endgame.
    var phase = (total * 256) ~/ _startTotal;
    if (phase > 256) {
      phase = 256;
    }
    final kingOpen =
        flyingKing ? EvalParams.flyingKingOpen : EvalParams.simpleKingOpen;
    final kingEnd =
        flyingKing ? EvalParams.flyingKingEnd : EvalParams.simpleKingEnd;

    var open = 0; // white-positive accumulators
    var end = 0;

    final whiteBB = engine.whiteBB;
    final blackBB = engine.blackBB;
    final kingsBB = engine.kingsBB;
    final occupied = whiteBB | blackBB;
    final neighbors = geometry.neighbors;

    // ---- men ----
    var bits = whiteBB & ~kingsBB;
    while (bits != 0) {
      final square = (bits & -bits).bitLength - 1;
      bits &= bits - 1;
      open += EvalParams.man + _manOpen[square];
      end += EvalParams.man + _manEnd[square];

      final structure = _manStructure(square, whiteBB, neighbors, white: true);
      open += structure;
      end += structure;

      // Runaway: nothing at all inside the promotion cone.
      if ((_whiteCone[square] & occupied) == 0) {
        final distance = geometry.rowOf(square); // rows to promotion
        if (distance <= 3 && engine.blackKings == 0) {
          final bonus =
              EvalParams.runawayBase + (3 - distance) * EvalParams.runawayPerRow;
          open += bonus;
          end += bonus + EvalParams.runawayPerRow;
        }
      }
    }
    bits = blackBB & ~kingsBB;
    while (bits != 0) {
      final square = (bits & -bits).bitLength - 1;
      bits &= bits - 1;
      final mirrored = _mirror[square];
      open -= EvalParams.man + _manOpen[mirrored];
      end -= EvalParams.man + _manEnd[mirrored];

      final structure = _manStructure(square, blackBB, neighbors, white: false);
      open -= structure;
      end -= structure;

      if ((_blackCone[square] & occupied) == 0) {
        final distance = size - 1 - geometry.rowOf(square);
        if (distance <= 3 && engine.whiteKings == 0) {
          final bonus =
              EvalParams.runawayBase + (3 - distance) * EvalParams.runawayPerRow;
          open -= bonus;
          end -= bonus + EvalParams.runawayPerRow;
        }
      }
    }

    // ---- kings ----
    bits = whiteBB & kingsBB;
    while (bits != 0) {
      final square = (bits & -bits).bitLength - 1;
      bits &= bits - 1;
      open += kingOpen;
      end += kingEnd;
      final mobility = _kingMobility(square, occupied, neighbors);
      open += mobility * EvalParams.kingMobilityOpen;
      end += mobility * EvalParams.kingMobilityEnd;
      if (mobility <= 1) {
        open += EvalParams.trappedKing;
        end += EvalParams.trappedKing;
      }
    }
    bits = blackBB & kingsBB;
    while (bits != 0) {
      final square = (bits & -bits).bitLength - 1;
      bits &= bits - 1;
      open -= kingOpen;
      end -= kingEnd;
      final mobility = _kingMobility(square, occupied, neighbors);
      open -= mobility * EvalParams.kingMobilityOpen;
      end -= mobility * EvalParams.kingMobilityEnd;
      if (mobility <= 1) {
        open -= EvalParams.trappedKing;
        end -= EvalParams.trappedKing;
      }
    }

    // ---- wing balance (10x10 men) ----
    if (size == 10) {
      final whiteLeft = _popCount(whiteBB & ~kingsBB & _leftWingMask);
      final whiteSkew = (2 * whiteLeft - engine.whiteMen).abs();
      if (whiteSkew > 2) {
        open += (whiteSkew - 2) * EvalParams.wingImbalance;
      }
      final blackLeft = _popCount(blackBB & ~kingsBB & _leftWingMask);
      final blackSkew = (2 * blackLeft - engine.blackMen).abs();
      if (blackSkew > 2) {
        open -= (blackSkew - 2) * EvalParams.wingImbalance;
      }
    }

    // ~/ keeps the taper symmetric for negative totals (>> rounds toward
    // negative infinity, which breaks color symmetry by one centi-man).
    var score = (open * phase + end * (256 - phase)) ~/ 256;

    // Ahead in material: trading pieces simplifies the win.
    final whiteMaterial = engine.whiteMen * 2 + engine.whiteKings * 5;
    final blackMaterial = engine.blackMen * 2 + engine.blackKings * 5;
    if (whiteMaterial != blackMaterial) {
      final removed = _startTotal - total;
      final bonus = removed * EvalParams.tradeWhenAhead;
      score += whiteMaterial > blackMaterial ? bonus : -bonus;
    }

    final mover = engine.sideToMove == PieceColor.white ? score : -score;
    return mover + EvalParams.tempo;
  }

  int _manStructure(
    int square,
    int ownBB,
    List<List<int>> neighbors, {
    required bool white,
  }) {
    // Rear diagonals: the directions this man came from.
    final rear1 = white ? BoardGeometry.southWest : BoardGeometry.northWest;
    final rear2 = white ? BoardGeometry.southEast : BoardGeometry.northEast;
    var value = 0;
    var hasNeighbor = false;
    final b1 = neighbors[rear1][square];
    if (b1 != -1 && (ownBB >> b1) & 1 == 1) {
      value += EvalParams.supportedMan;
      hasNeighbor = true;
    }
    final b2 = neighbors[rear2][square];
    if (b2 != -1 && (ownBB >> b2) & 1 == 1) {
      value += EvalParams.supportedMan;
      hasNeighbor = true;
    }
    if (!hasNeighbor) {
      final f1 = neighbors[white
          ? BoardGeometry.northWest
          : BoardGeometry.southWest][square];
      final f2 = neighbors[white
          ? BoardGeometry.northEast
          : BoardGeometry.southEast][square];
      final front1 = f1 != -1 && (ownBB >> f1) & 1 == 1;
      final front2 = f2 != -1 && (ownBB >> f2) & 1 == 1;
      if (!front1 && !front2) {
        value += EvalParams.isolatedMan;
      }
    }
    return value;
  }

  int _kingMobility(int square, int occupied, List<List<int>> neighbors) {
    var mobility = 0;
    for (final dir in BoardGeometry.allDirections) {
      var to = neighbors[dir][square];
      while (to != -1 && (occupied >> to) & 1 == 0) {
        mobility++;
        if (mobility >= EvalParams.kingMobilityCap || !flyingKing) {
          break;
        }
        to = neighbors[dir][to];
      }
      if (mobility >= EvalParams.kingMobilityCap) {
        break;
      }
    }
    return mobility;
  }
}
