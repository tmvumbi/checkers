import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../data/models/online_game.dart';
import '../../../engine/ai/ai_config.dart';
import '../../../engine/checkers_engine.dart';
import '../../../engine/move.dart';
import '../../../engine/rules_config.dart';
import '../../../routes/app_routes.dart';
import '../../../services/ad_service.dart';
import '../../../services/analytics_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/checkers_ai_service.dart';
import '../../../services/online_game_service.dart';
import '../../../services/profile_service.dart';
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
    OnlineGameService? onlineGameService,
    AuthService? authService,
    ProfileService? profileService,
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
       _onlineGameServiceOverride = onlineGameService,
       _authServiceOverride = authService,
       _profileServiceOverride = profileService,
       _aiMinThinkTime = aiMinThinkTime ?? const Duration(milliseconds: 800);

  final GameBoardArguments args;
  final AiService _aiService;
  final AnalyticsService _analyticsService;
  final OnlineGameService? _onlineGameServiceOverride;
  final AuthService? _authServiceOverride;
  final ProfileService? _profileServiceOverride;
  final Duration _aiMinThinkTime;

  // Resolved lazily so PC-mode tests need not register online services.
  OnlineGameService get _onlineGameService =>
      _onlineGameServiceOverride ?? Get.find();
  AuthService get _authService => _authServiceOverride ?? Get.find();

  late final CheckersEngine engine = CheckersEngine(config: args.rules);

  /// Monotonic counter bumped whenever board state changes (drives Obx).
  final RxInt boardVersion = 0.obs;
  final RxnInt selectedSquare = RxnInt();
  final Rxn<PieceAnimation> activeAnimation = Rxn<PieceAnimation>();
  final RxBool aiThinking = false.obs;
  final Rx<GameResult> result = GameResult.ongoing.obs;
  final Rx<ResultReason> resultReason = ResultReason.none.obs;

  // Online-only state.
  final Rxn<OnlineGameSnapshot> snapshot = Rxn<OnlineGameSnapshot>();
  final RxInt ownBankMs = 300000.obs;
  final RxInt opponentBankMs = 300000.obs;
  final RxInt turnRemainingMs = 15000.obs;
  final RxBool opponentConnected = true.obs;
  final RxBool drawOfferPending = false.obs;
  final RxBool incomingDrawOffer = false.obs;
  final RxBool rematchRequested = false.obs;
  final RxBool opponentWantsRematch = false.obs;
  int _drawOffersMade = 0;

  StreamSubscription<OnlineGameSnapshot>? _gameSubscription;
  Worker? _adEventWorker;
  Timer? _clockTimer;
  int _serverOffsetMs = 0;
  bool _timeoutClaimed = false;
  bool _applyingRemote = false;

  // Streamed PC game (recorded server-side when signed in; PRD update).
  String? _streamedGameId;
  bool _streamingEnabled = true;

  // Spectator presence for the watcher avatars row.
  final RxList<GameWatcher> watchers = <GameWatcher>[].obs;
  StreamSubscription<List<GameWatcher>>? _watchersSubscription;
  Timer? _watchHeartbeatTimer;

  /// The backend game id this board corresponds to, if any.
  String? get watchableGameId => isOnline ? args.gameId : _streamedGameId;

  PieceColor get humanColor => args.humanColor;

  bool get isOnline =>
      args.mode == GameBoardMode.online || args.mode == GameBoardMode.watching;

  bool get isWatching => args.mode == GameBoardMode.watching;

  OnlineGamePlayer? playerOfColor(PieceColor color) {
    final players = snapshot.value?.players;
    if (players == null) {
      return null;
    }
    for (final player in players) {
      if (player.color == color) {
        return player;
      }
    }
    return null;
  }

  /// Own profile photo for the local seat badge; snapshot players carry
  /// photos for online seats, but local PC games have no snapshot.
  final RxnString ownProfilePhotoUrl = RxnString();

  Future<void> _loadOwnProfilePhoto() async {
    try {
      final uid = _authService.currentUser?.uid;
      if (uid == null) {
        return;
      }
      final ProfileService profiles = _profileServiceOverride ?? Get.find();
      final result = await profiles.getProfile(uid);
      result.when(
        success: (profile) => ownProfilePhotoUrl.value = profile?.photoUrl,
        failure: (_) {},
      );
    } catch (_) {
      // No auth/profile service wired (offline/unit-test contexts).
    }
  }

  OnlineGamePlayer? get ownPlayer {
    final uid = _authService.currentUser?.uid;
    final players = snapshot.value?.players;
    if (uid == null || players == null) {
      return null;
    }
    for (final player in players) {
      if (player.uid == uid) {
        return player;
      }
    }
    return null;
  }

  OnlineGamePlayer? get opponentPlayer {
    final uid = _authService.currentUser?.uid;
    final players = snapshot.value?.players;
    if (players == null) {
      return null;
    }
    for (final player in players) {
      if (player.uid != uid) {
        return player;
      }
    }
    return null;
  }

  bool get isHumanTurn =>
      !isWatching &&
      engine.result == GameResult.ongoing &&
      result.value == GameResult.ongoing &&
      engine.sideToMove == humanColor &&
      activeAnimation.value == null;

  bool get canUndo =>
      args.mode == GameBoardMode.pc &&
      args.allowUndo &&
      engine.moveHistory.length >= 2 &&
      isHumanTurn;

  List<Move> get legalMoves => engine.legalMoves();

  @override
  void onReady() {
    super.onReady();
    if (!isWatching) {
      _loadOwnProfilePhoto();
    }
    // Finished PC games count toward the interstitial cadence (kopo parity).
    _adEventWorker = ever<GameResult>(result, (gameResult) {
      if (gameResult == GameResult.ongoing ||
          args.mode != GameBoardMode.pc ||
          !Get.isRegistered<AdService>()) {
        return;
      }
      unawaited(Get.find<AdService>().recordPcGameFinished());
    });
    _analyticsService.logEvent('game_started', {
      'mode': args.mode.name,
      'preset': args.rules.preset.name,
      'level': args.aiLevel?.name ?? 'none',
    });
    if (isOnline) {
      _startOnline();
      _startWatchersFeed(args.gameId!);
      if (isWatching) {
        _startWatcherPresence(args.gameId!);
      }
    } else {
      _startPcStreaming();
      _maybeTriggerAi();
    }
  }

  // -------------------------------------------------------------------
  // Streamed PC games
  // -------------------------------------------------------------------

  Future<void> _startPcStreaming() async {
    AuthUser? user;
    try {
      user = _authService.currentUser;
    } catch (_) {
      return; // No auth service wired (offline/unit-test contexts).
    }
    if (user == null) {
      return;
    }
    final result = await _onlineGameService.startPcGame(
      rules: args.rules,
      aiLevel: args.aiLevel!.name,
      allowUndo: args.allowUndo,
      humanColor: humanColor.name,
    );
    result.when(
      success: (gameId) {
        _streamedGameId = gameId;
        _streamingEnabled = true;
        _startWatchersFeed(gameId);
      },
      failure: (_) => _streamingEnabled = false,
    );
  }

  void _mirrorPcMove(Move move, int expectedPly) {
    final gameId = _streamedGameId;
    if (gameId == null || !_streamingEnabled) {
      return;
    }
    _onlineGameService.submitPcMove(gameId, move, expectedPly).then((result) {
      result.when(
        success: (_) {},
        failure: (_) => _streamingEnabled = false,
      );
    });
  }

  // -------------------------------------------------------------------
  // Watcher presence
  // -------------------------------------------------------------------

  void _startWatchersFeed(String gameId) {
    _watchersSubscription?.cancel();
    _watchersSubscription = _onlineGameService
        .watchWatchers(gameId)
        .listen((list) => watchers.value = list, onError: (_) {});
  }

  void _startWatcherPresence(String gameId) {
    _onlineGameService.watchHeartbeat(gameId);
    _watchHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _onlineGameService.watchHeartbeat(gameId),
    );
  }

  @override
  void onClose() {
    _gameSubscription?.cancel();
    _adEventWorker?.dispose();
    _clockTimer?.cancel();
    _watchersSubscription?.cancel();
    _watchHeartbeatTimer?.cancel();
    if (isOnline && !isWatching && args.gameId != null) {
      _onlineGameService.touchConnection(args.gameId!, false);
    }
    if (isWatching && args.gameId != null) {
      _onlineGameService.unwatchGame(args.gameId!);
    }
    // Quitting a streamed PC game mid-way counts as resigning it.
    final streamed = _streamedGameId;
    if (streamed != null &&
        _streamingEnabled &&
        result.value == GameResult.ongoing) {
      _onlineGameService.resignGame(streamed);
    }
    super.onClose();
  }

  // -------------------------------------------------------------------
  // Online wiring
  // -------------------------------------------------------------------

  Future<void> _startOnline() async {
    final gameId = args.gameId!;
    _serverOffsetMs = await _onlineGameService.serverTimeOffsetMs();
    if (!isWatching) {
      await _onlineGameService.touchConnection(gameId, true);
    }
    await _resyncFromServer();
    _gameSubscription = _onlineGameService
        .watchGame(gameId)
        .listen(_onSnapshot, onError: (_) {});
    _clockTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _tickClocks(),
    );
  }

  Future<void> _resyncFromServer() async {
    final gameId = args.gameId!;
    final snapshotResult = await _onlineGameService.fetchGame(gameId);
    final movesResult = await _onlineGameService.fetchMoves(gameId);
    snapshotResult.when(
      success: (snap) {
        movesResult.when(
          success: (moves) {
            engine.reset();
            for (final move in moves) {
              engine.applyMove(move);
            }
            snapshot.value = snap;
            _applyFinishedState(snap);
            boardVersion.value++;
          },
          failure: (_) {},
        );
      },
      failure: (_) {},
    );
  }

  Future<void> _onSnapshot(OnlineGameSnapshot snap) async {
    snapshot.value = snap;
    opponentConnected.value = opponentPlayer?.connected ?? true;

    // Draw-offer bookkeeping.
    final offer = snap.drawOfferColor;
    drawOfferPending.value = offer == humanColor;
    incomingDrawOffer.value = offer != null && offer != humanColor;

    // Rematch bookkeeping.
    final uid = _authService.currentUser?.uid;
    opponentWantsRematch.value = snap.rematchRequestedBy != null &&
        snap.rematchRequestedBy != uid;
    if (snap.rematchGameId != null && rematchRequested.value) {
      _navigateToRematch(snap.rematchGameId!);
      return;
    }

    if (_applyingRemote) {
      return;
    }
    if (snap.ply == engine.moveHistory.length + 1 && snap.lastMove != null) {
      // Opponent's (or our confirmed) next move: animate if it isn't ours.
      final mover = engine.sideToMove;
      _applyingRemote = true;
      try {
        if (isWatching || mover != humanColor) {
          await _animateAndApply(snap.lastMove!, movedByHuman: false);
        } else if (engine.moveHistory.length < snap.ply) {
          // Our own move already applied optimistically; nothing to do.
        }
      } finally {
        _applyingRemote = false;
      }
    } else if (snap.ply > engine.moveHistory.length + 1) {
      await _resyncFromServer();
    }
    _applyFinishedState(snap);
  }

  void _applyFinishedState(OnlineGameSnapshot snap) {
    if (!snap.isFinished) {
      return;
    }
    final mapped = switch (snap.result) {
      'whiteWin' => GameResult.whiteWin,
      'blackWin' => GameResult.blackWin,
      'draw' => GameResult.draw,
      _ => GameResult.draw,
    };
    ResultReason reason;
    try {
      reason = ResultReason.values.byName(snap.resultReason ?? 'none');
    } catch (_) {
      reason = ResultReason.none;
    }
    result.value = mapped;
    resultReason.value = reason;
  }

  void _tickClocks() {
    final snap = snapshot.value;
    if (snap == null || !snap.isPlaying) {
      return;
    }
    final ownIsWhite = humanColor == PieceColor.white;
    var ownBank = ownIsWhite ? snap.whiteBankMs : snap.blackBankMs;
    var oppBank = ownIsWhite ? snap.blackBankMs : snap.whiteBankMs;

    final now = DateTime.now().add(Duration(milliseconds: _serverOffsetMs));
    if (snap.turnStartedAt != null) {
      final elapsed = now.difference(snap.turnStartedAt!).inMilliseconds;
      final overrun = max(0, elapsed - 15000);
      turnRemainingMs.value = max(0, 15000 - elapsed);
      if (snap.sideToMove == humanColor) {
        ownBank = max(0, ownBank - overrun);
      } else {
        oppBank = max(0, oppBank - overrun);
      }
    }
    ownBankMs.value = ownBank;
    opponentBankMs.value = oppBank;

    if (snap.turnDeadlineAt != null &&
        now.isAfter(snap.turnDeadlineAt!.add(const Duration(seconds: 1))) &&
        !_timeoutClaimed) {
      _timeoutClaimed = true;
      _onlineGameService.claimTimeout(snap.id).then((_) {
        _timeoutClaimed = false;
      });
    }
  }

  // -------------------------------------------------------------------
  // Shared move handling
  // -------------------------------------------------------------------

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
    if (isOnline) {
      final expectedPly = engine.moveHistory.length;
      await _animateAndApply(move, movedByHuman: true);
      final submission = await _onlineGameService.submitMove(
        args.gameId!,
        move,
        expectedPly,
      );
      submission.when(
        success: (_) {},
        failure: (_) => _resyncFromServer(),
      );
    } else {
      await _animateAndApply(move, movedByHuman: true);
      await _maybeTriggerAi();
    }
  }

  Future<void> _animateAndApply(Move move, {required bool movedByHuman}) async {
    activeAnimation.value = PieceAnimation(
      move: move,
      movedByHuman: movedByHuman,
    );
    // One animation step per path segment; the view mirrors this timing.
    final segments = max(1, move.path.length);
    await Future<void>.delayed(Duration(milliseconds: 180 * segments + 120));
    final plyBeforeApply = engine.moveHistory.length;
    engine.applyMove(move);
    if (args.mode == GameBoardMode.pc) {
      _mirrorPcMove(move, plyBeforeApply);
    }
    activeAnimation.value = null;
    boardVersion.value++;
    if (!isOnline) {
      result.value = engine.result;
      resultReason.value = engine.resultReason;
    } else if (engine.result != GameResult.ongoing) {
      // Local engine reached a verdict; the authoritative one arrives with
      // the next snapshot, but mirror it for instant feedback.
      result.value = engine.result;
      resultReason.value = engine.resultReason;
    }
    if (result.value != GameResult.ongoing) {
      _analyticsService.logEvent('game_completed', {
        'mode': args.mode.name,
        'result': result.value.name,
        'reason': resultReason.value.name,
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
    final gameId = _streamedGameId;
    if (gameId != null && _streamingEnabled) {
      _onlineGameService.undoPcMoves(gameId, 2).then((response) {
        response.when(
          success: (_) {},
          failure: (_) => _streamingEnabled = false,
        );
      });
    }
  }

  void resign() {
    if (result.value != GameResult.ongoing) {
      return;
    }
    if (isOnline) {
      _onlineGameService.resignGame(args.gameId!);
      return; // Authoritative result arrives via the snapshot stream.
    }
    engine.declareResult(
      humanColor == PieceColor.white ? GameResult.blackWin : GameResult.whiteWin,
      ResultReason.resignation,
    );
    result.value = engine.result;
    resultReason.value = engine.resultReason;
    final gameId = _streamedGameId;
    if (gameId != null && _streamingEnabled) {
      _onlineGameService.resignGame(gameId);
    }
  }

  bool get canOfferDraw =>
      isOnline &&
      result.value == GameResult.ongoing &&
      !drawOfferPending.value &&
      !incomingDrawOffer.value &&
      _drawOffersMade < 3;

  Future<void> offerDraw() async {
    if (!canOfferDraw) {
      return;
    }
    _drawOffersMade++;
    drawOfferPending.value = true;
    await _onlineGameService.offerDraw(args.gameId!);
  }

  Future<void> respondDraw(bool accept) async {
    incomingDrawOffer.value = false;
    await _onlineGameService.respondDraw(args.gameId!, accept);
  }

  Future<void> requestRematch() async {
    if (!isOnline || rematchRequested.value) {
      return;
    }
    rematchRequested.value = true;
    final response = await _onlineGameService.requestRematch(args.gameId!);
    response.when(
      success: (data) {
        if (data.status == 'ready' && data.gameId != null) {
          _navigateToRematch(data.gameId!);
        }
      },
      failure: (_) => rematchRequested.value = false,
    );
  }

  void _navigateToRematch(String newGameId) {
    // Replacing the board route with itself makes GetX dispose the
    // controller after the new route resolved it (controller-not-found
    // crash). Rebuild the stack instead: home, then a fresh board.
    final arguments = GameBoardArguments.online(
      rules: args.rules,
      gameId: newGameId,
      humanColor: humanColor.opponent,
    );
    Get.offAllNamed<void>(AppRoutes.home);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.toNamed<void>(AppRoutes.gameBoard, arguments: arguments);
    });
  }

  void playAgain() {
    if (isOnline) {
      goHome();
      return;
    }
    engine.reset();
    selectedSquare.value = null;
    activeAnimation.value = null;
    result.value = engine.result;
    resultReason.value = engine.resultReason;
    boardVersion.value++;
    watchers.clear();
    _streamedGameId = null;
    _startPcStreaming(); // The server abandons the previous streamed game.
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
