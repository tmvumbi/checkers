import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../routes/app_routes.dart';
import '../shared/widgets/checkers_gradient_button.dart';
import '../shared/widgets/checkers_modal.dart';
import '../themes/app_theme.dart';
import '../translations/translation_keys.dart';

/// FCM plumbing for tournament reminders and administrator broadcasts.
///
/// - App in foreground and not on a board: an in-app modal offers to
///   join the lobby or dismiss.
/// - App backgrounded/closed: the system notification is shown by the
///   OS; tapping it routes straight into the tournament lobby.
class PushNotificationService extends GetxService with WidgetsBindingObserver {
  PushNotificationService({FirebaseMessaging? messaging})
    : _messagingOverride = messaging;

  final FirebaseMessaging? _messagingOverride;
  FirebaseMessaging get _messaging =>
      _messagingOverride ?? FirebaseMessaging.instance;

  StreamSubscription<RemoteMessage>? _onMessageSubscription;
  StreamSubscription<RemoteMessage>? _onOpenedSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<AuthState>? _authSubscription;
  bool _dialogOpen = false;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _wire();
  }

  Future<void> _wire() async {
    try {
      _onMessageSubscription = FirebaseMessaging.onMessage.listen(
        _onForegroundMessage,
        onError: (Object _) {},
      );
      _onOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _onOpenedFromNotification,
        onError: (Object _) {},
      );
      _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
        (token) => unawaited(_registerToken(token)),
        onError: (Object _) {},
      );
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((state) {
            if (state.session != null) {
              unawaited(syncRegistration());
            }
          }, onError: (Object _) {});
      final initial = await _messaging.getInitialMessage();
      if (initial != null) {
        _onOpenedFromNotification(initial);
      }
      await syncRegistration();
    } catch (_) {
      // No Firebase / no Play services: reminders silently unavailable.
    }
  }

  /// Asks for permission (first time) and returns this device's FCM
  /// token, or null when push is unavailable.
  Future<String?> requestToken() async {
    try {
      final settings = await _messaging.requestPermission();
      if (!_isAuthorized(settings.authorizationStatus)) {
        return null;
      }
      final token = await _messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }
      return token;
    } catch (_) {
      return null;
    }
  }

  /// Refreshes this device's platform and last-connection timestamp without
  /// prompting again when notification permission has not been granted.
  Future<void> syncRegistration() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      if (!_isAuthorized(settings.authorizationStatus)) {
        return;
      }
      final token = await _messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }
    } catch (_) {}
  }

  bool _isAuthorized(AuthorizationStatus status) =>
      status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;

  Future<void> _registerToken(String token) async {
    if (kIsWeb || Supabase.instance.client.auth.currentUser == null) {
      return;
    }
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
    if (platform == null) {
      return;
    }
    try {
      await Supabase.instance.client.rpc<void>(
        'register_push_device',
        params: {'p_token': token, 'p_platform': platform},
      );
    } catch (_) {
      // Registration is best-effort; gameplay must never depend on push.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(syncRegistration());
    }
  }

  bool _isTournamentSoon(RemoteMessage message) =>
      message.data['type'] == 'tournament_soon';

  void _onForegroundMessage(RemoteMessage message) {
    if (_isTournamentSoon(message)) {
      // Never interrupt someone playing or watching a game.
      if (Get.currentRoute == AppRoutes.gameBoard ||
          Get.currentRoute == AppRoutes.tournamentLobby) {
        return;
      }
      _showTournamentSoonDialog();
      return;
    }
    if (message.data['type'] == 'admin_broadcast') {
      if (Get.currentRoute == AppRoutes.gameBoard ||
          Get.currentRoute == AppRoutes.tournamentLobby) {
        return;
      }
      _showBroadcastDialog(message);
    }
  }

  void _onOpenedFromNotification(RemoteMessage message) {
    if (!_isTournamentSoon(message)) {
      return;
    }
    _goToLobby();
  }

  void _goToLobby() {
    if (Get.currentRoute == AppRoutes.tournamentLobby) {
      return;
    }
    // Joining happens automatically when the lobby screen opens. Cold
    // starts land here before routing settles; wait for the home screen.
    if (Get.currentRoute == AppRoutes.home) {
      Get.toNamed<void>(AppRoutes.tournamentLobby);
      return;
    }
    var attempts = 0;
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      attempts++;
      if (Get.currentRoute == AppRoutes.home) {
        timer.cancel();
        Get.toNamed<void>(AppRoutes.tournamentLobby);
      } else if (attempts > 20) {
        timer.cancel();
      }
    });
  }

  void _showTournamentSoonDialog() {
    if (_dialogOpen || Get.context == null) {
      return;
    }
    _dialogOpen = true;
    showCheckersModal<void>(
      context: Get.context!,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final brand = theme.extension<CheckersThemeExtension>()!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              TranslationKeys.tournamentSoonTitle.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium!.copyWith(
                color: brand.brandGold,
                fontSize: 24,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              TranslationKeys.tournamentSoonMessage.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge!.copyWith(
                color: theme.colorScheme.onPrimary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 20),
            CheckersGradientButton(
              key: const Key('tournament-soon-join'),
              label: TranslationKeys.tournamentSoonJoin.tr,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _goToLobby();
              },
            ),
            const SizedBox(height: 10),
            CheckersGradientButton(
              key: const Key('tournament-soon-decline'),
              label: TranslationKeys.decline.tr,
              gradientStyle: CheckersGradientButtonStyle.logo,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    ).whenComplete(() => _dialogOpen = false);
  }

  void _showBroadcastDialog(RemoteMessage message) {
    final title = message.notification?.title?.trim();
    final body = message.notification?.body?.trim();
    if (_dialogOpen || Get.context == null || body == null || body.isEmpty) {
      return;
    }
    _dialogOpen = true;
    showCheckersModal<void>(
      context: Get.context!,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final brand = theme.extension<CheckersThemeExtension>()!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title == null || title.isEmpty ? 'Checkers' : title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium!.copyWith(
                color: brand.brandGold,
                fontSize: 24,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge!.copyWith(
                color: theme.colorScheme.onPrimary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 20),
            CheckersGradientButton(
              label: TranslationKeys.ok.tr,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    ).whenComplete(() => _dialogOpen = false);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _onMessageSubscription?.cancel();
    _onOpenedSubscription?.cancel();
    _tokenRefreshSubscription?.cancel();
    _authSubscription?.cancel();
    super.onClose();
  }
}
