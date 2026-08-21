import 'dart:math';

import 'package:checkers/engine/ai/evaluator.dart';
import 'package:checkers/engine/checkers_engine.dart';
import 'package:checkers/engine/rules_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// The v2 evaluation must be color-symmetric: rotating the board 180° and
/// swapping colors (and the side to move) must negate nothing — the mover
/// sees the exact same game, so the score must be identical.
void main() {
  test('evaluation is symmetric under 180° rotation with colors swapped', () {
    for (final rules in [
      RulesConfig.international,
      RulesConfig.brazilian,
      RulesConfig.american,
    ]) {
      final evaluator = Evaluator.forConfig(
        CheckersEngine(config: rules).geometry,
        flying: rules.flyingKing,
      );
      final count = rules.squareCount;
      final random = Random(7);

      for (var trial = 0; trial < 200; trial++) {
        // Random position: up to 8 pieces per side, men not on their
        // promotion rows (illegal there), some kings.
        final taken = <int>{};
        final whiteMen = <int>[], blackMen = <int>[], kings = <int>[];
        int? place(bool king, bool white) {
          for (var attempt = 0; attempt < 30; attempt++) {
            final square = random.nextInt(count);
            final row = square ~/ (rules.boardSize ~/ 2);
            if (!king && white && row == 0) continue;
            if (!king && !white && row == rules.boardSize - 1) continue;
            if (taken.add(square)) return square;
          }
          return null;
        }

        for (var i = random.nextInt(6) + 2; i > 0; i--) {
          final king = random.nextInt(4) == 0;
          final square = place(king, true);
          if (square == null) continue;
          whiteMen.add(square);
          if (king) kings.add(square);
        }
        for (var i = random.nextInt(6) + 2; i > 0; i--) {
          final king = random.nextInt(4) == 0;
          final square = place(king, false);
          if (square == null) continue;
          blackMen.add(square);
          if (king) kings.add(square);
        }
        if (whiteMen.isEmpty || blackMen.isEmpty) continue;

        final engine = CheckersEngine(config: rules);
        engine.loadPosition(
          whiteSquares: whiteMen,
          blackSquares: blackMen,
          kingSquares: kings,
        );
        final score = evaluator.evaluate(engine);

        // Mirrored: 180° rotation, colors swapped, black-equivalent mover.
        final mirrored = CheckersEngine(config: rules);
        mirrored.loadPosition(
          whiteSquares: [for (final s in blackMen) count - 1 - s],
          blackSquares: [for (final s in whiteMen) count - 1 - s],
          kingSquares: [for (final s in kings) count - 1 - s],
          side: PieceColor.black,
        );
        final mirroredScore = evaluator.evaluate(mirrored);

        expect(
          mirroredScore,
          score,
          reason: '${rules.preset} trial $trial: eval must be symmetric',
        );
      }
    }
  });
}
