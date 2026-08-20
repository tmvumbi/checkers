import 'package:checkers/engine/ai/ai_config.dart';
import 'package:checkers/engine/checkers_engine.dart';
import 'package:checkers/engine/rules_config.dart';
import 'package:checkers/modules/game_board/controller/game_board_controller.dart';
import 'package:checkers/modules/game_board/models/game_board_arguments.dart';
import 'package:checkers/services/analytics_service.dart';
import 'package:checkers/services/checkers_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

GameBoardController _pcController({
  RulesConfig rules = RulesConfig.international,
  bool allowUndo = true,
}) {
  return GameBoardController(
    arguments: GameBoardArguments.pc(
      rules: rules,
      aiLevel: AiLevel.easy,
      humanColor: PieceColor.white,
      allowUndo: allowUndo,
    ),
    aiService: SyncAiService(),
    analyticsService: NoopAnalyticsService(),
    aiMinThinkTime: Duration.zero,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(Get.reset);

  test('human move triggers an AI reply', () async {
    final controller = _pcController();
    final move = controller.legalMoves.first;

    controller.onSquareTapped(move.from);
    expect(controller.selectedSquare.value, move.from);
    controller.onSquareTapped(move.to);

    // Wait out both animation windows (human + AI).
    await Future<void>.delayed(const Duration(milliseconds: 3500));
    expect(controller.engine.moveHistory.length, 2);
    expect(controller.engine.sideToMove, PieceColor.white);
  });

  test('tapping a non-selectable square clears the selection', () {
    final controller = _pcController();
    final move = controller.legalMoves.first;
    controller.onSquareTapped(move.from);
    expect(controller.selectedSquare.value, isNotNull);
    // Square 25 area: pick a square with no white piece.
    controller.onSquareTapped(21);
    expect(controller.selectedSquare.value, isNull);
  });

  test('undo removes the last human+AI exchange', () async {
    final controller = _pcController();
    final move = controller.legalMoves.first;
    controller.onSquareTapped(move.from);
    controller.onSquareTapped(move.to);
    await Future<void>.delayed(const Duration(milliseconds: 3500));
    expect(controller.engine.moveHistory.length, 2);
    expect(controller.canUndo, isTrue);

    controller.undoLastExchange();
    expect(controller.engine.moveHistory, isEmpty);
    expect(controller.engine.sideToMove, PieceColor.white);
  });

  test('undo stays unavailable when not opted in at setup', () async {
    final controller = _pcController(allowUndo: false);
    final move = controller.legalMoves.first;
    controller.onSquareTapped(move.from);
    controller.onSquareTapped(move.to);
    await Future<void>.delayed(const Duration(milliseconds: 3500));
    expect(controller.engine.moveHistory.length, 2);
    expect(controller.canUndo, isFalse);
  });

  test('resign ends the game against the human', () {
    final controller = _pcController();
    controller.resign();
    expect(controller.result.value, GameResult.blackWin);
    expect(controller.resultReason.value, ResultReason.resignation);
    expect(controller.humanWon, isFalse);
  });

  test('playAgain resets the board', () async {
    final controller = _pcController();
    controller.resign();
    controller.playAgain();
    expect(controller.result.value, GameResult.ongoing);
    expect(controller.engine.moveHistory, isEmpty);
    expect(controller.legalMoves.length, 9);
  });
}
