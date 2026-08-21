import 'dart:math';

import 'package:checkers/engine/checkers_engine.dart';
import 'package:checkers/engine/ai/ai_config.dart';
import 'package:checkers/engine/rules_config.dart';
import 'package:checkers/services/checkers_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'persistent AI isolate plays a game with rewinds and stays legal',
    () async {
      final service = PersistentIsolateAiService();
      addTearDown(service.dispose);
      final engine = CheckersEngine(config: RulesConfig.brazilian);
      final random = Random(42);

      for (var round = 0; round < 5; round++) {
        // "Human" plays a random legal move…
        final humanMoves = engine.legalMoves();
        if (humanMoves.isEmpty || engine.result != GameResult.ongoing) {
          break;
        }
        engine.applyMove(humanMoves[random.nextInt(humanMoves.length)]);
        if (engine.result != GameResult.ongoing) {
          break;
        }

        // …the warm isolate answers with a legal one.
        final aiMove = await service.chooseMove(engine, AiLevel.easy);
        final legalKeys = engine.legalMoves().map((m) => m.key).toSet();
        expect(legalKeys, contains(aiMove.key), reason: 'round $round');
        engine.applyMove(engine.legalMoves()
            .firstWhere((move) => move.key == aiMove.key));

        // Rewind one exchange mid-game: the next request resyncs fully.
        if (round == 2 && engine.moveHistory.length >= 2) {
          engine.undoMove();
          engine.undoMove();
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
