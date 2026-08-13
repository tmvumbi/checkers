import 'dart:async';
import 'dart:math';

import 'package:get/get.dart';

import '../../../engine/ai/ai_config.dart';
import '../../../engine/checkers_engine.dart';
import '../../../engine/move.dart';
import '../../../engine/rules_config.dart';
import '../../../routes/app_routes.dart';
import '../../../services/analytics_service.dart';
import '../../../services/checkers_ai_service.dart';
import '../models/game_board_arguments.dart';

/// Board-square animation step for multi-hop capture rendering.
class PieceAnimation {
  const PieceAnimation({required this.move, required this.movedByHuman});

  final Move move;
  final bool movedByHuman;
}

class GameBoardController extends GetxController {
  GameBoardController({
    GameBoardArguments? arguments,
    AiService? aiService,
    AnalyticsService? analyticsService,
    Duration? aiMinThinkTime,
  }) : args =
           arguments ??
           (Get.arguments as GameBoardArguments? ??
               const GameBoardArguments.pc(
                 rules: RulesConfig.international,
                 aiLevel: AiLevel.medium,
                 humanColor: PieceColor.white,
               )),
       _aiService = aiService ?? Get.find(),
       _analyticsService = analyticsService ?? Get.find(),
       _aiMinThinkTime = aiMinThinkTime ?? const Duration(milliseconds: 800);

  final GameBoardArguments args;
  final AiService _aiService;
  final AnalyticsService _analyticsService;
  final Duration _aiMinThinkTime;

  late final CheckersEngine engine = CheckersEngine(config: args.rules);

  /// Monotonic counter bumped whenever board state changes (drives Obx).
  final RxInt boardVersion = 0.obs;
  final RxnInt selectedSquare = RxnInt();
  final Rxn<PieceAnimation> activeAnimation = Rxn<PieceAnimation>();
  final RxBool aiThinking = false.obs;
  final Rx<GameResult> result = GameResult.ongoing.obs;
  final Rx<ResultReason> resultReason = ResultReason.none.obs;

  PieceColor get humanColor => args.humanColor;

  bool get isHumanTurn =>
      engine.result == GameResult.ongoing &&
      engine.sideToMove == humanColor &&
      activeAnimation.value == null;

  bool get canUndo =>
      args.mode == GameBoardMode.pc &&
      engine.moveHistory.length >= 2 &&
      isHumanTurn;

  List<Move> get legalMoves => engine.legalMoves();

  @override
  void onReady() {
    super.onReady();
    _analyticsService.logEvent('game_started', {
      'mode': args.mode.name,
      'preset': args.rules.preset.name,
      'level': args.aiLevel?.name ?? 'none',
    });
    _maybeTriggerAi();
  }

  /// Legal moves currently available from [square].
  List<Move> movesFrom(int square) {
    return [
      for (final move in legalMoves)
        if (move.from == square) move,
    ];
  }

  /// Squares the human may currently pick up.
  Set<int> get selectableSquares {
    if (!isHumanTurn) {
      return const {};
    }
    return {for (final move in legalMoves) move.from};
  }

  void onSquareTapped(int square) {
    if (!isHumanTurn) {
      return;
    }
    final selected = selectedSquare.value;
    if (selected != null) {
      final candidates = [
        for (final move in movesFrom(selected))
          if (move.to == square) move,
      ];
      if (candidates.isNotEmpty) {
        selectedSquare.value = null;
        _playHumanMove(candidates.first);
        return;
      }
    }
    if (selectableSquares.contains(square)) {
      selectedSquare.value = square == selected ? null : square;
    } else {
      selectedSquare.value = null;
    }
  }

  Future<void> _playHumanMove(Move move) async {
    await _animateAndApply(move, movedByHuman: true);
    await _maybeTriggerAi();
  }

  Future<void> _animateAndApply(Move move, {required bool movedByHuman}) async {
    activeAnimation.value = PieceAnimation(
      move: move,
      movedByHuman: movedByHuman,
    );
    // One animation step per path segment; the view mirrors this timing.
    final segments = max(1, move.path.length);
    await Future<void>.delayed(Duration(milliseconds: 180 * segments + 120));
    engine.applyMove(move);
    activeAnimation.value = null;
    boardVersion.value++;
    result.value = engine.result;
    resultReason.value = engine.resultReason;
    if (engine.result != GameResult.ongoing) {
      _analyticsService.logEvent('game_completed', {
        'mode': args.mode.name,
        'result': engine.result.name,
        'reason': engine.resultReason.name,
      });
    }
  }

  Future<void> _maybeTriggerAi() async {
    if (args.mode != GameBoardMode.pc ||
        engine.result != GameResult.ongoing ||
        engine.sideToMove == humanColor) {
      return;
    }
    aiThinking.value = true;
    final started = DateTime.now();
    Move move;
    try {
      move = await _aiService.chooseMove(engine, args.aiLevel!);
    } finally {
      aiThinking.value = false;
    }
    final elapsed = DateTime.now().difference(started);
    if (elapsed < _aiMinThinkTime) {
      await Future<void>.delayed(_aiMinThinkTime - elapsed);
    }
    await _animateAndApply(move, movedByHuman: false);
  }

  void undoLastExchange() {
    if (!canUndo) {
      return;
    }
    engine.undoMove();
    engine.undoMove();
    selectedSquare.value = null;
    boardVersion.value++;
    result.value = engine.result;
    resultReason.value = engine.resultReason;
  }

  void resign() {
    if (engine.result != GameResult.ongoing) {
      return;
    }
    engine.declareResult(
      humanColor == PieceColor.white ? GameResult.blackWin : GameResult.whiteWin,
      ResultReason.resignation,
    );
    result.value = engine.result;
    resultReason.value = engine.resultReason;
  }

  void playAgain() {
    engine.reset();
    selectedSquare.value = null;
    activeAnimation.value = null;
    result.value = engine.result;
    resultReason.value = engine.resultReason;
    boardVersion.value++;
    _maybeTriggerAi();
  }

  void goHome() {
    Get.offAllNamed<void>(AppRoutes.home);
  }

  bool get humanWon =>
      (result.value == GameResult.whiteWin &&
          humanColor == PieceColor.white) ||
      (result.value == GameResult.blackWin && humanColor == PieceColor.black);
}
