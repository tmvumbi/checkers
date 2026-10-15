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

  _watchReplayTests();

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

// Appended: watch-to-replay handoff and progress-bar scrubbing.
void _watchReplayTests() {
  test('dismissWatchResult parks a finished game on its last move', () {
    final controller = _pcController();
    // Watch mode replays every move through the engine, so seeding the
    // engine directly mirrors the state a finished watched game holds.
    for (var i = 0; i < 4; i++) {
      controller.engine.applyMove(controller.engine.legalMoves().first);
    }

    controller.dismissWatchResult();

    expect(controller.watchReplayActive.value, isTrue);
    expect(controller.replayUiActive, isTrue);
    expect(controller.replayTotal.value, 4);
    expect(controller.replayIndex.value, 4);
    expect(controller.engine.moveHistory.length, 4);
  });

  test('replaySeek jumps to any position and clamps out-of-range', () {
    final controller = _pcController();
    for (var i = 0; i < 4; i++) {
      controller.engine.applyMove(controller.engine.legalMoves().first);
    }
    controller.dismissWatchResult();

    controller.replaySeek(0);
    expect(controller.replayIndex.value, 0);
    expect(controller.engine.moveHistory, isEmpty);

    controller.replaySeek(2);
    expect(controller.replayIndex.value, 2);
    expect(controller.engine.moveHistory.length, 2);

    controller.replaySeek(99);
    expect(controller.replayIndex.value, 4);
    expect(controller.engine.moveHistory.length, 4);

    controller.replaySeek(-3);
    expect(controller.replayIndex.value, 0);
  });
}
