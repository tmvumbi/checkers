import '../../../engine/ai/ai_config.dart';
import '../../../engine/checkers_engine.dart';
import '../../../engine/rules_config.dart';

enum GameBoardMode { pc, online, watching }

class GameBoardArguments {
  const GameBoardArguments.pc({
    required this.rules,
    required this.aiLevel,
    required this.humanColor,
  }) : mode = GameBoardMode.pc,
       gameId = null;

  const GameBoardArguments.online({
    required this.rules,
    required this.gameId,
    required this.humanColor,
  }) : mode = GameBoardMode.online,
       aiLevel = null;

  const GameBoardArguments.watching({required this.rules, required this.gameId})
    : mode = GameBoardMode.watching,
      aiLevel = null,
      humanColor = PieceColor.white;

  final GameBoardMode mode;
  final RulesConfig rules;
  final AiLevel? aiLevel;
  final PieceColor humanColor;
  final String? gameId;
}
