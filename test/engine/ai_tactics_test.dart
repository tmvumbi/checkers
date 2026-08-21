import 'package:checkers/engine/ai/ai_config.dart';
import 'package:checkers/engine/ai/checkers_ai.dart';
import 'package:checkers/engine/checkers_engine.dart';
import 'package:checkers/engine/rules_config.dart';
import 'package:flutter_test/flutter_test.dart';

AiConfig _fixedDepth(int depth) => AiConfig(
  level: AiLevel.hard,
  maxDepth: depth,
  budgetMs: 100000,
  topN: 1,
  pickSecondBestChance: 0,
  blunderChance: 0,
  noiseCentiMen: 0,
);

/// Small tactical regression net: unsound pruning or ordering bugs show up
/// here before they show up against players.
void main() {
  test('runs a runaway man home instead of shuffling', () {
    final engine = CheckersEngine(config: RulesConfig.international);
    // White man on 7 has a completely clear path to promotion; the rest of
    // the position is inert. Depth 8 must start the run immediately.
    engine.loadPosition(
      whiteSquares: [7, 41, 43, 46, 48],
      blackSquares: [20, 22, 24, 15, 17],
    );
    final choice = CheckersAi(engine, _fixedDepth(8)).chooseMove();
    expect(
      choice.move.from,
      7,
      reason: 'should push the runaway man (played ${choice.move.key})',
    );
  });

  test('avoids the advance that walks into a fork', () {
    // Mirrors the long-standing poisoned-advance test but through the new
    // hard search path with all features on.
    final engine = CheckersEngine(config: RulesConfig.international);
    engine.loadPosition(
      whiteSquares: [30, 33, 36, 38, 41, 43, 45, 47],
      blackSquares: [4, 6, 9, 11, 13, 16, 18, 21],
    );
    final choice = CheckersAi(engine, _fixedDepth(8)).chooseMove();
    // Whatever it plays must not immediately lose material by force:
    // verify with a shallow refutation search from the reply side.
    engine.applyMove(choice.move);
    final replies = engine.legalMoves();
    final anyCapture = replies.any((move) => move.isCapture);
    expect(
      anyCapture,
      isFalse,
      reason: 'hard handed the opponent a capture: ${choice.move.key}',
    );
  });

  test('takes the safe recapture, not the poisoned one (american rules)', () {
    // American rules: no majority-capture filter, so equal-length capture
    // choices are real decisions. White on 17 must jump 13 (landing 8,
    // where black 5 recaptures) or 14 (landing 10, safe).
    final engine = CheckersEngine(config: RulesConfig.american);
    engine.loadPosition(
      whiteSquares: [17, 28, 29],
      blackSquares: [13, 14, 5, 0],
    );
    final choice = CheckersAi(engine, _fixedDepth(8)).chooseMove();
    expect(choice.move.isCapture, isTrue);
    engine.applyMove(choice.move);
    final counterCapture = engine
        .legalMoves()
        .any((move) => move.isCapture);
    expect(
      counterCapture,
      isFalse,
      reason: 'chose a capture that gets recaptured: ${choice.move.key}',
    );
  });
}
