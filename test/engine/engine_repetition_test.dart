import 'dart:math';

import 'package:checkers/engine/checkers_engine.dart';
import 'package:checkers/engine/rules_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bounded threefold-repetition scan must be exactly equivalent to
/// scanning the entire hash history.
void main() {
  test('bounded repetition scan matches a full-history scan', () {
    for (final rules in [
      RulesConfig.international,
      RulesConfig.brazilian,
      RulesConfig.american,
    ]) {
      for (var seed = 0; seed < 12; seed++) {
        final engine = CheckersEngine(config: rules);
        final random = Random(seed);
        final hashes = <int>[engine.hash];

        for (var ply = 0; ply < 240; ply++) {
          if (engine.result != GameResult.ongoing) {
            break;
          }
          final moves = engine.legalMoves();
          if (moves.isEmpty) {
            break;
          }
          engine.applyMove(moves[random.nextInt(moves.length)]);
          hashes.add(engine.hash);

          // Reference: full scan over every position seen so far.
          var repetitions = 0;
          for (final h in hashes) {
            if (h == engine.hash) {
              repetitions++;
            }
          }
          final fullScanSaysDraw = repetitions >= 3;
          final engineSaysRepetitionDraw =
              engine.result == GameResult.draw &&
              engine.resultReason == ResultReason.repetition;
          if (fullScanSaysDraw) {
            expect(
              engineSaysRepetitionDraw,
              isTrue,
              reason:
                  'seed $seed ${rules.preset} ply $ply: full scan found a '
                  'threefold the bounded scan missed',
            );
            break;
          } else {
            expect(
              engineSaysRepetitionDraw,
              isFalse,
              reason:
                  'seed $seed ${rules.preset} ply $ply: bounded scan '
                  'declared a repetition the full scan disproves',
            );
          }
        }
      }
    }
  });

  test('king shuffle still reaches a threefold repetition draw', () {
    final engine = CheckersEngine(config: RulesConfig.international);
    engine.loadPosition(
      whiteSquares: [45],
      blackSquares: [0],
      kingSquares: [45, 0],
    );
    // Shuffle both kings back and forth on fixed squares until the same
    // position with the same side to move occurs three times.
    var draw = false;
    for (var cycle = 0; cycle < 12 && !draw; cycle++) {
      for (final target in [40, 45]) {
        final whiteMove = engine
            .legalMoves()
            .firstWhere((move) => move.to == target);
        engine.applyMove(whiteMove);
        if (engine.result == GameResult.draw) {
          draw = true;
          break;
        }
        final blackTarget = engine.sideToMove == PieceColor.black
            ? (engine.isBlackAt(0) ? 5 : 0)
            : null;
        if (blackTarget == null) {
          break;
        }
        final blackMove = engine
            .legalMoves()
            .firstWhere((move) => move.to == blackTarget);
        engine.applyMove(blackMove);
        if (engine.result == GameResult.draw) {
          draw = true;
          break;
        }
      }
    }
    expect(draw, isTrue);
    expect(engine.resultReason, ResultReason.repetition);
  });
}
