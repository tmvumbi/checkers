import 'dart:async';

import 'package:get/get.dart';

import '../../../data/models/tournament.dart';
import '../../../routes/app_routes.dart';
import '../../../services/analytics_service.dart';
import '../../../services/push_notification_service.dart';
import '../../../services/tournament_service.dart';
import '../../../shared/widgets/checkers_snackbar.dart';
import '../../../translations/translation_keys.dart';

/// Tournament waiting room: realtime presence, heartbeats, and a poll
/// that moves everyone along the moment the tournament starts.
class TournamentLobbyController extends GetxController {
  TournamentLobbyController({
    TournamentService? tournamentService,
    AnalyticsService? analyticsService,
  }) : _tournamentService = tournamentService ?? Get.find(),
       _analyticsService = analyticsService ?? Get.find();

  final TournamentService _tournamentService;
  final AnalyticsService _analyticsService;

  final RxList<TournamentLobbyPlayer> players = <TournamentLobbyPlayer>[].obs;
  final RxString countdown = ''.obs;
  final RxBool joining = true.obs;

  /// Transient "not enough players" notice after a missed start tick.
  final RxnString missedTickNotice = RxnString();
  Timer? _missedTickTimer;
  int _lastRemainingSeconds = 0;

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
    _analyticsService.logEvent('tournament_lobby_joined');
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

    // The remaining time jumping back up means a start tick just passed;
    // if the room was too small, say so instead of failing silently.
    if (remaining.inSeconds > _lastRemainingSeconds &&
        _lastRemainingSeconds > 0 &&
        players.length < 4) {
      final next = now.add(remaining);
      final hh = next.hour.toString().padLeft(2, '0');
      final nm = next.minute.toString().padLeft(2, '0');
      missedTickNotice.value = TranslationKeys.tournamentMissedTick.trParams({
        'time': '$hh:$nm',
      });
      _missedTickTimer?.cancel();
      _missedTickTimer = Timer(const Duration(seconds: 10), () {
        missedTickNotice.value = null;
      });
    }
    _lastRemainingSeconds = remaining.inSeconds;
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
    _analyticsService.logEvent('tournament_started');
    // Always land on the bracket, which opens the player's match itself and
    // keeps doing so each round. Going straight to the board here would
    // leave the bracket out of the back stack, stranding the player on the
    // result screen when the match ended.
    Get.offNamed<void>(AppRoutes.tournament, arguments: state.tournamentId);
  }

  void leave() {
    Get.back<void>();
  }

  /// Leaves the lobby but registers this device for a push reminder one
  /// minute before the next tournament starts.
  Future<void> leaveAndNotify() async {
    String? token;
    if (Get.isRegistered<PushNotificationService>()) {
      token = await Get.find<PushNotificationService>().requestToken();
    }
    if (token == null) {
      Get.back<void>();
      showCheckersSnackbar(TranslationKeys.tournamentNotifyUnavailable.tr);
      return;
    }
    final result = await _tournamentService.optInNotify(token);
    final ok = result.when(success: (_) => true, failure: (_) => false);
    // Pop first: Get.back with a snackbar open dismisses the snackbar
    // instead of the route.
    Get.back<void>();
    showCheckersSnackbar(
      ok
          ? TranslationKeys.tournamentNotifySet.tr
          : TranslationKeys.tournamentNotifyUnavailable.tr,
    );
  }

  @override
  void onClose() {
    _lobbySubscription?.cancel();
    _heartbeatTimer?.cancel();
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _missedTickTimer?.cancel();
    // Quitting the screen (or the app killing it) leaves the lobby; a
    // stale heartbeat covers crashes and lost connections server-side.
    _tournamentService.leaveLobby();
    super.onClose();
  }
}
