import 'dart:async';

import 'package:get/get.dart';

import '../../../data/models/online_game.dart';
import '../../../engine/checkers_engine.dart';
import '../../../routes/app_routes.dart';
import '../../../services/analytics_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/online_game_service.dart';
import '../../game_board/models/game_board_arguments.dart';

class OnlineLobbyArguments {
  const OnlineLobbyArguments({required this.preset});

  final String preset;
}

class OnlineLobbyController extends GetxController {
  OnlineLobbyController({
    OnlineLobbyArguments? arguments,
    OnlineGameService? onlineGameService,
    AuthService? authService,
    AnalyticsService? analyticsService,
  }) : args =
           arguments ??
           (Get.arguments as OnlineLobbyArguments? ??
               const OnlineLobbyArguments(preset: 'international')),
       _onlineGameService = onlineGameService ?? Get.find(),
       _authService = authService ?? Get.find(),
       _analyticsService = analyticsService ?? Get.find();

  final OnlineLobbyArguments args;
  final OnlineGameService _onlineGameService;
  final AuthService _authService;
  final AnalyticsService _analyticsService;

  final Rxn<OnlineGameSnapshot> snapshot = Rxn<OnlineGameSnapshot>();
  final RxBool failed = false.obs;
  final RxnString gameId = RxnString();

  StreamSubscription<OnlineGameSnapshot>? _subscription;
  Timer? _startupTimeout;
  bool _navigated = false;

  @override
  void onReady() {
    super.onReady();
    _join();
  }

  Future<void> _join() async {
    await _analyticsService.logEvent('online_join_attempt', {
      'preset': args.preset,
    });
    final result = await _onlineGameService.joinOnlineGame(args.preset);
    result.when(
      success: (joined) {
        gameId.value = joined.gameId;
        _subscription = _onlineGameService
            .watchGame(joined.gameId)
            .listen(_onSnapshot, onError: (_) => failed.value = true);
        // Kopo's 8s no-first-snapshot timeout.
        _startupTimeout = Timer(const Duration(seconds: 8), () {
          if (snapshot.value == null) {
            failed.value = true;
          }
        });
        // The stream may already miss the initial row; fetch once.
        _onlineGameService.fetchGame(joined.gameId).then((fetched) {
          fetched.when(
            success: _onSnapshot,
            failure: (_) {},
          );
        });
      },
      failure: (_) => failed.value = true,
    );
  }

  void _onSnapshot(OnlineGameSnapshot snap) {
    snapshot.value = snap;
    if (snap.isPlaying && !_navigated) {
      _navigated = true;
      final uid = _authService.currentUser?.uid;
      PieceColor color = PieceColor.white;
      for (final player in snap.players) {
        if (player.uid == uid && player.color != null) {
          color = player.color!;
        }
      }
      _subscription?.cancel();
      Get.offNamed<void>(
        AppRoutes.gameBoard,
        arguments: GameBoardArguments.online(
          rules: snap.rules,
          gameId: snap.id,
          humanColor: color,
        ),
      );
    }
  }

  Future<void> leaveLobby() async {
    final id = gameId.value;
    if (id != null) {
      await _onlineGameService.leaveGame(id);
    }
    Get.offAllNamed<void>(AppRoutes.home);
  }

  @override
  void onClose() {
    _subscription?.cancel();
    _startupTimeout?.cancel();
    super.onClose();
  }
}
