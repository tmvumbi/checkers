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
       gameId = null,
       tournamentId = null;

  const GameBoardArguments.online({
    required this.rules,
    required this.gameId,
    required this.humanColor,
    this.tournamentId,
  }) : mode = GameBoardMode.online,
       aiLevel = null,
       allowUndo = false;

  const GameBoardArguments.watching({required this.rules, required this.gameId})
    : mode = GameBoardMode.watching,
      aiLevel = null,
      humanColor = PieceColor.white,
      allowUndo = false,
      tournamentId = null;

  /// Step through a recorded (finished) game.
  const GameBoardArguments.replay({required this.rules, required this.gameId})
    : mode = GameBoardMode.replay,
      aiLevel = null,
      humanColor = PieceColor.white,
      allowUndo = false,
      tournamentId = null;

  final GameBoardMode mode;
  final RulesConfig rules;
  final AiLevel? aiLevel;
  final PieceColor humanColor;
  final String? gameId;

  /// PC games only: whether the player opted in to undoing moves.
  final bool allowUndo;

  /// Set when this online game is a tournament match: the board then sends
  /// the player back to the bracket instead of offering a rematch, and
  /// follows them into the next round as soon as it is paired.
  final String? tournamentId;

  bool get isTournamentMatch =>
      mode == GameBoardMode.online && tournamentId != null;
}
