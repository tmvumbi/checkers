import 'dart:async';

import 'package:get/get.dart';

import '../../../data/models/online_game.dart';
import '../../../data/models/tournament.dart';
import '../../../engine/checkers_engine.dart';
import '../../../modules/game_board/models/game_board_arguments.dart';
import '../../../routes/app_routes.dart';
import '../../../services/auth_service.dart';
import '../../../services/online_game_service.dart';
import '../../../services/tournament_service.dart';
import '../../../shared/widgets/checkers_snackbar.dart';
import '../../../translations/translation_keys.dart';

/// Tournament waiting room: realtime presence, heartbeats, and a poll
/// that moves everyone along the moment the tournament starts.
class TournamentLobbyController extends GetxController {
  TournamentLobbyController({
    TournamentService? tournamentService,
    OnlineGameService? onlineGameService,
    AuthService? authService,
  }) : _tournamentService = tournamentService ?? Get.find(),
       _onlineGameServiceOverride = onlineGameService,
       _authServiceOverride = authService;

  final TournamentService _tournamentService;
  final OnlineGameService? _onlineGameServiceOverride;
  final AuthService? _authServiceOverride;

  OnlineGameService get _onlineGameService =>
      _onlineGameServiceOverride ?? Get.find();
  AuthService get _authService => _authServiceOverride ?? Get.find();

  final RxList<TournamentLobbyPlayer> players = <TournamentLobbyPlayer>[].obs;
  final RxString countdown = ''.obs;
  final RxBool joining = true.obs;

  StreamSubscription<List<TournamentLobbyPlayer>>? _lobbySubscription;
  Timer? _heartbeatTimer;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  bool _navigatingToTournament = false;

  @override
  void onReady() {
    super.onReady();
    _join();
  }

  Future<void> _join() async {
    final result = await _tournamentService.joinLobby();
    final failed = result.when(success: (_) => false, failure: (_) => true);
    if (failed) {
      showCheckersSnackbar(TranslationKeys.tournamentJoinFailed.tr);
      Get.back<void>();
      return;
    }
    joining.value = false;
    _lobbySubscription = _tournamentService.watchLobby().listen(
      players.assignAll,
      onError: (Object _) {},
    );
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _tournamentService.touchLobby(),
    );
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _checkStarted(),
    );
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickCountdown(),
    );
    _tickCountdown();
  }

  void _tickCountdown() {
    final now = DateTime.now();
    final minutes = now.minute >= 30 ? 60 - now.minute : 30 - now.minute;
    final remaining = Duration(minutes: minutes) -
        Duration(seconds: now.second);
    final mm = remaining.inMinutes.toString().padLeft(2, '0');
    final ss = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    countdown.value = '$mm:$ss';
  }

  Future<void> _checkStarted() async {
    if (_navigatingToTournament) {
      return;
    }
    final result = await _tournamentService.myTournamentState();
    final state = result.when(
      success: (value) => value,
      failure: (_) => const MyTournamentState(),
    );
    if (state.tournamentId == null || _navigatingToTournament) {
      return;
    }
    _navigatingToTournament = true;
    final gameId = state.gameId;
    if (gameId != null) {
      await _openMyGame(gameId, state.tournamentId!);
    } else {
      Get.offNamed<void>(
        AppRoutes.tournament,
        arguments: state.tournamentId,
      );
    }
  }

  Future<void> _openMyGame(String gameId, String tournamentId) async {
    final result = await _onlineGameService.fetchGame(gameId);
    final snapshot = result.when<OnlineGameSnapshot?>(
      success: (value) => value,
      failure: (_) => null,
    );
    if (snapshot == null) {
      Get.offNamed<void>(AppRoutes.tournament, arguments: tournamentId);
      return;
    }
    final uid = _authService.currentUser?.uid;
    final me = snapshot.players
        .where((player) => player.uid == uid)
        .toList();
    Get.offNamed<void>(
      AppRoutes.gameBoard,
      arguments: GameBoardArguments.online(
        rules: snapshot.rules,
        gameId: gameId,
        humanColor: me.isEmpty
            ? PieceColor.white
            : (me.first.color ?? PieceColor.white),
      ),
    );
  }

  void leave() {
    Get.back<void>();
  }

  @override
  void onClose() {
    _lobbySubscription?.cancel();
    _heartbeatTimer?.cancel();
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    // Quitting the screen (or the app killing it) leaves the lobby; a
    // stale heartbeat covers crashes and lost connections server-side.
    _tournamentService.leaveLobby();
    super.onClose();
  }
}
