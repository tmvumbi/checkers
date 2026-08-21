import 'package:checkers/engine/ai/ai_config.dart';
import 'package:checkers/engine/ai/checkers_ai.dart';
import 'package:checkers/engine/board_geometry.dart';
import 'package:checkers/engine/checkers_engine.dart';
import 'package:checkers/engine/rules_config.dart';
import 'package:flutter_test/flutter_test.dart';

int idx10(int row, int col) => BoardGeometry.forSize(10).indexOf(row, col)!;

void main() {
  group('CheckersAi', () {
    test('always returns a legal move from the initial position', () {
      final engine = CheckersEngine(config: RulesConfig.international);
      for (final level in AiLevel.values) {
        final ai = CheckersAi(engine, AiConfig.forLevel(level));
        final choice = ai.chooseMove();
        final legalKeys = engine.legalMoves().map((m) => m.key).toSet();
        expect(legalKeys, contains(choice.move.key));
      }
    });

    test('hard AI is deterministic for the same position and seed', () {
      final engine = CheckersEngine(config: RulesConfig.international);
      const quick = AiConfig(
        level: AiLevel.hard,
        maxDepth: 6,
        budgetMs: 100000, // effectively depth-limited, so runs are identical
        topN: 1,
        pickSecondBestChance: 0,
        blunderChance: 0,
        noiseCentiMen: 0,
      );
      final first = CheckersAi(engine, quick, rngSeed: 42).chooseMove();
      final second = CheckersAi(engine, quick, rngSeed: 42).chooseMove();
      expect(first.move.key, second.move.key);
    });

    test('hard AI randomizes only among near-equal best moves', () {
      const quick = AiConfig(
        level: AiLevel.hard,
        maxDepth: 6,
        budgetMs: 100000,
        topN: 1,
        pickSecondBestChance: 0,
        blunderChance: 0,
        noiseCentiMen: 0,
      );
      final baseline = CheckersAi(
        CheckersEngine(config: RulesConfig.international),
        quick,
        rngSeed: 0,
      ).chooseMove();
      for (var seed = 1; seed <= 8; seed++) {
        final choice = CheckersAi(
          CheckersEngine(config: RulesConfig.international),
          quick,
          rngSeed: seed,
        ).chooseMove();
        // Whatever the seed picks must score within a tenth of a man of the
        // best move (the opening is symmetric enough to have such ties).
        expect(baseline.score - choice.score, lessThanOrEqualTo(10));
      }
    });

    test('hard AI avoids the poisoned advance that loses a man', () {
      // White man on (5,4); black men on (3,2) and (3,6) with backup on
      // (2,5). Advancing to (4,5) lets black capture with a protected
      // recapture; advancing to (4,3) is safe. Depth 4 sees it.
      final engine = CheckersEngine(config: RulesConfig.international)
        ..loadPosition(
          whiteSquares: [idx10(5, 4), idx10(9, 0), idx10(9, 2)],
          blackSquares: [idx10(3, 6), idx10(2, 5), idx10(0, 1)],
        );
      const config = AiConfig(
        level: AiLevel.hard,
        maxDepth: 6,
        budgetMs: 100000,
        topN: 1,
        pickSecondBestChance: 0,
        blunderChance: 0,
        noiseCentiMen: 0,
      );
      final choice = CheckersAi(engine, config).chooseMove();
      // Moving 5,4 -> 4,5 hangs the man to 3,6 (recapture protected by 2,5).
      final poisoned = choice.move.from == idx10(5, 4) &&
          choice.move.to == idx10(4, 5);
      expect(poisoned, isFalse);
    });

    test('AI vs AI game reaches a verdict (no infinite games)', () {
      final engine = CheckersEngine(config: RulesConfig.brazilian);
      const fast = AiConfig(
        level: AiLevel.hard,
        maxDepth: 4,
        budgetMs: 150,
        topN: 1,
        pickSecondBestChance: 0,
        blunderChance: 0,
        noiseCentiMen: 0,
      );
      var plies = 0;
      while (engine.result == GameResult.ongoing && plies < 300) {
        final choice = CheckersAi(engine, fast).chooseMove();
        engine.applyMove(choice.move);
        plies++;
      }
      expect(engine.result, isNot(GameResult.ongoing),
          reason: 'game should finish; lasted $plies plies');
    });

    test('search depth on a mid-game position is meaningful', () {
      final engine = CheckersEngine(config: RulesConfig.international);
      // Play a few book-less opening plies.
      for (var i = 0; i < 8; i++) {
        engine.applyMove(engine.legalMoves().first);
      }
      final choice = CheckersAi(engine, AiConfig.easy).chooseMove();
      expect(choice.depth, greaterThanOrEqualTo(4));
    });

    test('difficulty ladder is ordered: hard searches deeper than easy', () {
      final engine = CheckersEngine(config: RulesConfig.international);
      // Advance to a mid-game position that offers a real choice of moves
      // (a single forced capture would short-circuit the search at depth 0).
      var plies = 0;
      while (plies < 30 &&
          (plies < 10 || engine.legalMoves().length <= 2)) {
        engine.applyMove(engine.legalMoves().first);
        plies++;
      }
      expect(engine.legalMoves().length, greaterThan(2));
      final easy = CheckersAi(
        CheckersEngine.fromJson(engine.toJson()),
        AiConfig.easy,
      ).chooseMove();
      final hard = CheckersAi(
        CheckersEngine.fromJson(engine.toJson()),
        AiConfig.hard,
      ).chooseMove();
      expect(hard.depth, greaterThan(easy.depth));
      expect(hard.depth, greaterThanOrEqualTo(10));
    });
  });
}
