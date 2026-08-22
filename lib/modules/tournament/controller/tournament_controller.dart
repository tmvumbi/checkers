import 'dart:async';

import 'package:get/get.dart';

import '../../../data/models/online_game.dart';
import '../../../data/models/tournament.dart';
import '../../../engine/checkers_engine.dart';
import '../../../modules/game_board/models/game_board_arguments.dart';
import '../../../routes/app_routes.dart';
import '../../../services/analytics_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/online_game_service.dart';
import '../../../services/tournament_service.dart';

enum TournamentViewMode { fixtures, table }

/// Live bracket for one tournament: fixtures + table views, realtime
/// match updates, and auto-navigation into the viewer's own match.
class TournamentController extends GetxController {
  TournamentController({
    String? tournamentId,
    TournamentService? tournamentService,
    OnlineGameService? onlineGameService,
    AuthService? authService,
    AnalyticsService? analyticsService,
  }) : tournamentId = tournamentId ?? (Get.arguments as String),
       _tournamentService = tournamentService ?? Get.find(),
       _onlineGameServiceOverride = onlineGameService,
       _authServiceOverride = authService,
       _analyticsService = analyticsService ?? Get.find();

  final String tournamentId;
  final TournamentService _tournamentService;
  final OnlineGameService? _onlineGameServiceOverride;
  final AuthService? _authServiceOverride;
  final AnalyticsService _analyticsService;
  bool _endedLogged = false;

  OnlineGameService get _onlineGameService =>
      _onlineGameServiceOverride ?? Get.find();
  AuthService get _authService => _authServiceOverride ?? Get.find();

  final Rxn<TournamentDetail> detail = Rxn<TournamentDetail>();
  final Rx<TournamentViewMode> viewMode = TournamentViewMode.fixtures.obs;
  final RxBool myMatchReady = false.obs;
  String? _myPendingGameId;

  /// Matches this screen has already taken the player into, so backing out
  /// of a game does not immediately re-open it.
  final Set<String> _openedGameIds = <String>{};
  bool _openingGame = false;

  StreamSubscription<List<TournamentMatch>>? _matchesSubscription;
  Timer? _refreshTimer;

  bool get amParticipant {
    final uid = _authService.currentUser?.uid;
    return detail.value?.players.any((player) => player.uid == uid) ?? false;
  }

  TournamentPlayer? playerOf(String uid) {
    final players = detail.value?.players;
    if (players == null) {
      return null;
    }
    for (final player in players) {
      if (player.uid == uid) {
        return player;
      }
    }
    return null;
  }

  @override
  void onReady() {
    super.onReady();
    refreshDetail();
    _matchesSubscription = _tournamentService
        .watchMatches(tournamentId)
        .listen((_) => refreshDetail(), onError: (Object _) {});
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => refreshDetail(),
    );
  }

  Future<void> refreshDetail() async {
    final result = await _tournamentService.fetchTournamentDetail(
      tournamentId,
    );
    result.when(
      success: (value) {
        final wasFinished = detail.value?.summary.isFinished ?? true;
        detail.value = value;
        _checkMyPendingMatch(value);
        if (!wasFinished && value.summary.isFinished && !_endedLogged) {
          _endedLogged = true;
          _analyticsService.logEvent('tournament_ended', {
            'participants': value.summary.participantCount,
          });
        }
      },
      failure: (_) {},
    );
  }

  void _checkMyPendingMatch(TournamentDetail value) {
    final uid = _authService.currentUser?.uid;
    if (uid == null || value.summary.isFinished) {
      myMatchReady.value = false;
      return;
    }
    final mine = value.matches
        .where(
          (match) =>
              !match.isFinished &&
              match.gameId != null &&
              (match.p1Uid == uid || match.p2Uid == uid),
        )
        .toList();
    _myPendingGameId = mine.isEmpty ? null : mine.first.gameId;
    myMatchReady.value = _myPendingGameId != null;
    _maybeAutoOpen();
  }

  /// A paired match is already on the clock, so take the player into it
  /// rather than waiting for them to notice the button. Each match is
  /// opened at most once: a player who deliberately backs out of their
  /// game must not be dragged straight back in.
  void _maybeAutoOpen() {
    final gameId = _myPendingGameId;
    if (gameId == null || _openedGameIds.contains(gameId) || _openingGame) {
      return;
    }
    _openedGameIds.add(gameId);
    unawaited(playMyMatch());
  }

  Future<void> playMyMatch() async {
    final gameId = _myPendingGameId;
    if (gameId == null) {
      return;
    }
    await _openGame(gameId, asPlayer: true);
  }

  Future<void> openMatch(TournamentMatch match) async {
    final gameId = match.gameId;
    if (gameId == null) {
      return;
    }
    final uid = _authService.currentUser?.uid;
    final isMine =
        !match.isFinished && (match.p1Uid == uid || match.p2Uid == uid);
    await _openGame(gameId, asPlayer: isMine);
  }

  Future<void> _openGame(String gameId, {required bool asPlayer}) async {
    if (_openingGame) {
      return;
    }
    _openingGame = true;
    try {
      await _openGameInner(gameId, asPlayer: asPlayer);
    } finally {
      _openingGame = false;
    }
  }

  Future<void> _openGameInner(String gameId, {required bool asPlayer}) async {
    final result = await _onlineGameService.fetchGame(gameId);
    final snapshot = result.when<OnlineGameSnapshot?>(
      success: (value) => value,
      failure: (_) => null,
    );
    if (snapshot == null) {
      return;
    }
    if (asPlayer && snapshot.isPlaying) {
      final uid = _authService.currentUser?.uid;
      final me = snapshot.players
          .where((player) => player.uid == uid)
          .toList();
      await Get.toNamed<void>(
        AppRoutes.gameBoard,
        arguments: GameBoardArguments.online(
          rules: snapshot.rules,
          gameId: gameId,
          humanColor: me.isEmpty
              ? PieceColor.white
              : (me.first.color ?? PieceColor.white),
          tournamentId: tournamentId,
        ),
      );
    } else if (snapshot.isPlaying) {
      await Get.toNamed<void>(
        AppRoutes.gameBoard,
        arguments: GameBoardArguments.watching(
          rules: snapshot.rules,
          gameId: gameId,
        ),
      );
    } else {
      // Finished: rewatch the recorded game.
      await Get.toNamed<void>(
        AppRoutes.gameBoard,
        arguments: GameBoardArguments.replay(
          rules: snapshot.rules,
          gameId: gameId,
        ),
      );
    }
    refreshDetail();
  }

  @override
  void onClose() {
    _matchesSubscription?.cancel();
    _refreshTimer?.cancel();
    super.onClose();
  }
}
