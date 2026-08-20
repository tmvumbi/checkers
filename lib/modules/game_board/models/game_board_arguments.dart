import '../../../engine/ai/ai_config.dart';
import '../../../engine/checkers_engine.dart';
import '../../../engine/rules_config.dart';

enum GameBoardMode { pc, online, watching, replay }

class GameBoardArguments {
  const GameBoardArguments.pc({
    required this.rules,
    required this.aiLevel,
    required this.humanColor,
    this.allowUndo = false,
  }) : mode = GameBoardMode.pc,
       gameId = null;

  const GameBoardArguments.online({
    required this.rules,
    required this.gameId,
    required this.humanColor,
  }) : mode = GameBoardMode.online,
       aiLevel = null,
       allowUndo = false;

  const GameBoardArguments.watching({required this.rules, required this.gameId})
    : mode = GameBoardMode.watching,
      aiLevel = null,
      humanColor = PieceColor.white,
      allowUndo = false;

  /// Step through a recorded (finished) game.
  const GameBoardArguments.replay({required this.rules, required this.gameId})
    : mode = GameBoardMode.replay,
      aiLevel = null,
      humanColor = PieceColor.white,
      allowUndo = false;

  final GameBoardMode mode;
  final RulesConfig rules;
  final AiLevel? aiLevel;
  final PieceColor humanColor;
  final String? gameId;

  /// PC games only: whether the player opted in to undoing moves.
  final bool allowUndo;
}
