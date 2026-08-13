import 'package:checkers/engine/board_geometry.dart';
import 'package:checkers/engine/checkers_engine.dart';
import 'package:checkers/engine/move.dart';
import 'package:checkers/engine/rules_config.dart';
import 'package:flutter_test/flutter_test.dart';

// Square helpers: engine squares are 0-based FMJD indices. idx(row, col)
// converts board coordinates (0-based, row 0 = Black's back row) for
// readability in test setups.
int idx10(int row, int col) => BoardGeometry.forSize(10).indexOf(row, col)!;
int idx8(int row, int col) => BoardGeometry.forSize(8).indexOf(row, col)!;

void main() {
  group('geometry', () {
    test('FMJD 10x10 numbering landmarks', () {
      final geometry = BoardGeometry.forSize(10);
      expect(geometry.squareCount, 50);
      // FMJD squares 1..5 are the top row, 46..50 the bottom row.
      expect(geometry.rowOf(0), 0);
      expect(geometry.rowOf(45), 9);
      // Square 46 (index 45) and square 5 (index 4) are the long-diagonal
      // corners (FMJD Art. 2.6.3).
      expect(geometry.colOf(4), 9);
      expect(geometry.colOf(45), 0);
    });

    test('neighbor tables are mutually consistent', () {
      for (final size in const [8, 10]) {
        final geometry = BoardGeometry.forSize(size);
        for (var square = 0; square < geometry.squareCount; square++) {
          final nw = geometry.neighbors[BoardGeometry.northWest][square];
          if (nw != -1) {
            expect(geometry.neighbors[BoardGeometry.southEast][nw], square);
          }
          final ne = geometry.neighbors[BoardGeometry.northEast][square];
          if (ne != -1) {
            expect(geometry.neighbors[BoardGeometry.southWest][ne], square);
          }
        }
      }
    });
  });

  group('initial position', () {
    test('international: 20 men each, white to move, 9 opening moves', () {
      final engine = CheckersEngine(config: RulesConfig.international);
      expect(engine.legalMoves().length, 9);
      expect(engine.sideToMove, PieceColor.white);
    });

    test('american 8x8: 12 men each, 7 opening moves', () {
      final engine = CheckersEngine(config: RulesConfig.american);
      expect(engine.legalMoves().length, 7);
    });
  });

  group('capture rules', () {
    test('mandatory capture: quiet moves are illegal when a capture exists',
        () {
      final engine = CheckersEngine(config: RulesConfig.international)
        ..loadPosition(
          whiteSquares: [idx10(5, 4), idx10(9, 0)],
          blackSquares: [idx10(4, 3)],
        );
      final moves = engine.legalMoves();
      expect(moves.every((move) => move.isCapture), isTrue);
      expect(moves, hasLength(1));
      expect(moves.single.captured, [idx10(4, 3)]);
    });

    test('majority rule: the longest sequence is obligatory', () {
      // White man can take 1 piece one way or 2 the other; majority forces 2.
      final engine = CheckersEngine(config: RulesConfig.brazilian)
        ..loadPosition(
          whiteSquares: [idx8(5, 2)],
          blackSquares: [idx8(4, 1), idx8(4, 3), idx8(2, 3)],
        );
      final moves = engine.legalMoves();
      expect(moves.every((move) => move.captured.length == 2), isTrue);
    });

    test('without majority rule any capture may be chosen (American)', () {
      final engine = CheckersEngine(config: RulesConfig.american)
        ..loadPosition(
          whiteSquares: [idx8(5, 2)],
          blackSquares: [idx8(4, 1), idx8(4, 3), idx8(2, 3)],
        );
      final lengths =
          engine.legalMoves().map((move) => move.captured.length).toSet();
      expect(lengths, containsAll([1, 2]));
    });

    test('backward capture by men follows the toggle', () {
      // Enemy directly behind the white man.
      final brazilian = CheckersEngine(config: RulesConfig.brazilian)
        ..loadPosition(
          whiteSquares: [idx8(3, 2)],
          blackSquares: [idx8(4, 3)],
        );
      expect(brazilian.legalMoves().any((move) => move.isCapture), isTrue);

      final american = CheckersEngine(config: RulesConfig.american)
        ..loadPosition(
          whiteSquares: [idx8(3, 2)],
          blackSquares: [idx8(4, 3)],
        );
      expect(american.legalMoves().any((move) => move.isCapture), isFalse);
    });

    test('man may cross the same empty square twice in a cycle', () {
      // Four enemies around a loop; the man captures all four and lands
      // back on its origin square.
      final engine = CheckersEngine(config: RulesConfig.brazilian)
        ..loadPosition(
          whiteSquares: [idx8(5, 2)],
          blackSquares: [idx8(4, 3), idx8(2, 3), idx8(2, 1), idx8(4, 1)],
        );
      final moves = engine.legalMoves();
      expect(moves.first.captured.length, 4);
      expect(moves.first.to, idx8(5, 2));
    });

    test('Turkish strike: a dead piece blocks the landing square '
        '(FMJD Art. 4.11)', () {
      // King chain A -> B -> C; a fourth enemy P is then adjacent, but the
      // only landing square beyond P is occupied by the already-captured A.
      // A buggy engine that removes pieces immediately would capture 4.
      final a = idx10(4, 3), b = idx10(1, 4), c = idx10(1, 2), p = idx10(3, 2);
      final engine = CheckersEngine(config: RulesConfig.international)
        ..loadPosition(
          whiteSquares: [idx10(5, 2)],
          kingSquares: [idx10(5, 2)],
          blackSquares: [a, b, c, p],
        );
      final moves = engine.legalMoves();
      final maxCaptured = moves
          .map((move) => move.captured.length)
          .reduce((x, y) => x > y ? x : y);
      expect(maxCaptured, 3);
      for (final move in moves) {
        expect(move.captured, isNot(contains(p)));
      }
    });

    test('flying king chooses any landing square beyond the captured piece',
        () {
      final engine = CheckersEngine(config: RulesConfig.international)
        ..loadPosition(
          whiteSquares: [idx10(9, 0)],
          kingSquares: [idx10(9, 0)],
          blackSquares: [idx10(6, 3)],
        );
      final moves = engine.legalMoves();
      // Landings: (5,4), (4,5), (3,6), (2,7), (1,8), (0,9).
      expect(moves, hasLength(6));
      expect(moves.every((move) => move.captured.single == idx10(6, 3)),
          isTrue);
    });

    test('non-flying king moves and captures one square only', () {
      final engine = CheckersEngine(config: RulesConfig.american)
        ..loadPosition(
          whiteSquares: [idx8(5, 2)],
          kingSquares: [idx8(5, 2)],
          blackSquares: [idx8(4, 3)],
        );
      final moves = engine.legalMoves();
      expect(moves, hasLength(1));
      expect(moves.single.to, idx8(3, 4));
      expect(moves.single.captured.single, idx8(4, 3));
    });
  });

  group('promotion', () {
    test('quiet move onto the back row promotes', () {
      final engine = CheckersEngine(config: RulesConfig.international)
        ..loadPosition(
          whiteSquares: [idx10(1, 2)],
          blackSquares: [idx10(9, 8)],
        );
      final promotion = engine
          .legalMoves()
          .firstWhere((move) => move.promotes);
      engine.applyMove(promotion);
      expect(engine.isKingAt(promotion.to), isTrue);
    });

    test('man passing over the promotion row mid-capture stays a man '
        '(FMJD Art. 4.15)', () {
      final engine = CheckersEngine(config: RulesConfig.international)
        ..loadPosition(
          whiteSquares: [idx10(2, 5)],
          blackSquares: [idx10(1, 4), idx10(1, 2), idx10(9, 8)],
        );
      final moves = engine.legalMoves();
      final best = moves.first;
      expect(best.captured.length, 2);
      expect(best.to, idx10(2, 1));
      expect(best.promotes, isFalse);
      engine.applyMove(best);
      expect(engine.isKingAt(idx10(2, 1)), isFalse);
    });

    test('capture ending on the promotion row promotes', () {
      final engine = CheckersEngine(config: RulesConfig.international)
        ..loadPosition(
          whiteSquares: [idx10(2, 5)],
          blackSquares: [idx10(1, 4), idx10(9, 8)],
        );
      final best = engine.legalMoves().first;
      expect(best.to, idx10(0, 3));
      expect(best.promotes, isTrue);
      engine.applyMove(best);
      expect(engine.isKingAt(idx10(0, 3)), isTrue);
    });
  });

  group('terminal and draw rules', () {
    test('capturing the last piece wins', () {
      final engine = CheckersEngine(config: RulesConfig.international)
        ..loadPosition(
          whiteSquares: [idx10(5, 4)],
          blackSquares: [idx10(4, 3)],
        );
      engine.applyMove(engine.legalMoves().single);
      expect(engine.result, GameResult.whiteWin);
      expect(engine.resultReason, ResultReason.noPieces);
    });

    test('a blocked opponent loses', () {
      // Black man trapped in the corner: its quiet move is blocked and the
      // jump landing square is occupied.
      final engine = CheckersEngine(config: RulesConfig.international)
        ..loadPosition(
          whiteSquares: [
            idx10(1, 8),
            idx10(2, 7),
            idx10(2, 9),
            idx10(9, 0),
            idx10(9, 2),
          ],
          blackSquares: [idx10(0, 9)],
          side: PieceColor.white,
        );
      // White plays a quiet move elsewhere; black (0,9) has SW blocked by
      // (1,8) and no other move.
      final quiet = engine
          .legalMoves()
          .firstWhere((move) => move.from == idx10(9, 0));
      engine.applyMove(quiet);
      expect(engine.result, GameResult.whiteWin);
      expect(engine.resultReason, ResultReason.blocked);
    });

    test('threefold repetition is a draw', () {
      // Kings shuttle on diagonals that never intersect, so no capture ever
      // becomes mandatory.
      final engine = CheckersEngine(config: RulesConfig.international)
        ..loadPosition(
          whiteSquares: [idx10(9, 0)],
          kingSquares: [idx10(9, 0), idx10(0, 5)],
          blackSquares: [idx10(0, 5)],
        );

      Move findMove(CheckersEngine e, int from, int to) =>
          e.legalMoves().firstWhere((m) => m.from == from && m.to == to);

      final w1 = idx10(9, 0), w2 = idx10(8, 1);
      final b1 = idx10(0, 5), b2 = idx10(1, 4);
      // Shuffle kings back and forth; the initial position recurs.
      engine
        ..applyMove(findMove(engine, w1, w2))
        ..applyMove(findMove(engine, b1, b2))
        ..applyMove(findMove(engine, w2, w1))
        ..applyMove(findMove(engine, b2, b1))
        ..applyMove(findMove(engine, w1, w2))
        ..applyMove(findMove(engine, b1, b2))
        ..applyMove(findMove(engine, w2, w1))
        ..applyMove(findMove(engine, b2, b1));
      expect(engine.result, GameResult.draw);
      expect(engine.resultReason, ResultReason.repetition);
    });

    test('5-move endgame rule declares the draw (1K vs 1K)', () {
      final engine = CheckersEngine(config: RulesConfig.international)
        ..loadPosition(
          whiteSquares: [idx10(9, 0)],
          kingSquares: [idx10(9, 0), idx10(2, 5)],
          blackSquares: [idx10(2, 5)],
        );
      // Play king moves avoiding repetition until the countdown fires.
      var plies = 0;
      while (engine.result == GameResult.ongoing && plies < 12) {
        final moves = engine.legalMoves();
        engine.applyMove(moves[plies % moves.length]);
        plies++;
      }
      expect(engine.result, GameResult.draw);
      expect(
        engine.resultReason,
        anyOf(ResultReason.endgame5, ResultReason.repetition),
      );
      expect(plies, lessThanOrEqualTo(10));
    });

    test('undo restores position, counters, and result', () {
      final engine = CheckersEngine(config: RulesConfig.international);
      final before = engine.hash;
      final move = engine.legalMoves().first;
      engine.applyMove(move);
      engine.undoMove();
      expect(engine.hash, before);
      expect(engine.sideToMove, PieceColor.white);
      expect(engine.moveHistory, isEmpty);
      expect(engine.legalMoves().length, 9);
    });

    test('serialization roundtrip preserves state', () {
      final engine = CheckersEngine(config: RulesConfig.international);
      for (var i = 0; i < 6; i++) {
        engine.applyMove(engine.legalMoves().first);
      }
      final restored = CheckersEngine.fromJson(engine.toJson());
      expect(restored.hash, engine.hash);
      expect(restored.sideToMove, engine.sideToMove);
      expect(restored.whiteBB, engine.whiteBB);
      expect(restored.blackBB, engine.blackBB);
      expect(restored.kingsBB, engine.kingsBB);
    });
  });
}
