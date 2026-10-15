import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'auth_service.dart';
import 'convex/convex_gateway.dart';

/// Backend half of [PresenceService].
abstract class PresenceBackend {
  Future<void> heartbeat({required String busyMode});
  Future<void> leave();
}

class ConvexPresenceBackend implements PresenceBackend {
  ConvexPresenceBackend({ConvexGateway? gateway}) : _gatewayOverride = gateway;

  final ConvexGateway? _gatewayOverride;
  ConvexGateway get _convex => _gatewayOverride ?? Get.find<ConvexGateway>();

  @override
  Future<void> heartbeat({required String busyMode}) async {
    await _convex.mutation('presence:heartbeat', {'busyMode': busyMode});
  }

  @override
  Future<void> leave() async {
    await _convex.mutation('presence:leave');
  }
}

/// Keeps this player's row in `player_presence` fresh while signed in —
/// powers the invite-a-friend directory (kopo's availablePlayers).
///
/// Heartbeats only run while the app is foregrounded: backgrounding
/// removes the presence row right away (otherwise timers keep firing in
/// the background and the player looks online forever).
class PresenceService extends GetxService with WidgetsBindingObserver {
  PresenceService({PresenceBackend? backend, AuthService? authService})
    : _backendOverride = backend,
      _authServiceOverride = authService;

  final PresenceBackend? _backendOverride;
  final AuthService? _authServiceOverride;
  PresenceBackend get _backend => _backendOverride ?? Get.find();
  AuthService get _auth => _authServiceOverride ?? Get.find();

  Timer? _timer;
  String _busyMode = 'idle';
  bool _foreground = true;
  StreamSubscription<AuthUser?>? _authSubscription;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = _auth.userChanges.listen((user) {
      if (user != null) {
        start();
      } else {
        stop();
      }
    });
    if (_auth.currentUser != null) {
      start();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        if (_auth.currentUser != null) {
          start();
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _foreground = false;
        stop();
        _leave();
      case AppLifecycleState.inactive:
        // Transient (app switcher peek, permission dialogs): keep the
        // heartbeat, the paused state follows if the user really left.
        break;
    }
  }

  void start() {
    if (!_foreground) {
      return;
    }
    _timer?.cancel();
    _beat();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => _beat());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void setBusyMode(String mode) {
    _busyMode = mode;
    _beat();
  }

  Future<void> _beat() async {
    try {
      await _backend.heartbeat(busyMode: _busyMode);
    } catch (_) {
      // Presence is best-effort.
    }
  }

  Future<void> _leave() async {
    if (_auth.currentUser == null) {
      return;
    }
    try {
      await _backend.leave();
    } catch (_) {
      // The 3-minute server sweep covers missed goodbyes.
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    stop();
    super.onClose();
  }
}
