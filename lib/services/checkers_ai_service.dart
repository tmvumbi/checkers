import 'dart:convert';
import 'dart:isolate';

import '../engine/ai/ai_config.dart';
import '../engine/ai/checkers_ai.dart';
import '../engine/checkers_engine.dart';
import '../engine/move.dart';

/// Runs the AI search off the UI isolate (PRD §7.3).
abstract class AiService {
  Future<Move> chooseMove(CheckersEngine engine, AiLevel level);
}

class IsolateAiService implements AiService {
  @override
  Future<Move> chooseMove(CheckersEngine engine, AiLevel level) async {
    final engineJson = jsonEncode(engine.toJson());
    final levelName = level.name;
    final moveJson = await Isolate.run(() {
      final rebuilt = CheckersEngine.fromJson(
        jsonDecode(engineJson) as Map<String, dynamic>,
      );
      final ai = CheckersAi(rebuilt, AiConfig.forLevel(AiLevel.values.byName(levelName)));
      return jsonEncode(ai.chooseMove().move.toJson());
    });
    return Move.fromJson(jsonDecode(moveJson) as Map<String, dynamic>);
  }
}

/// Synchronous variant for tests.
class SyncAiService implements AiService {
  @override
  Future<Move> chooseMove(CheckersEngine engine, AiLevel level) async {
    final rebuilt = CheckersEngine.fromJson(engine.toJson());
    final ai = CheckersAi(rebuilt, AiConfig.forLevel(level));
    return ai.chooseMove().move;
  }
}
