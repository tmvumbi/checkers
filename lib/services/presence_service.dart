import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps this player's row in `player_presence` fresh while signed in —
/// powers the invite-a-friend directory (kopo's availablePlayers).
///
/// Heartbeats only run while the app is foregrounded: backgrounding
/// removes the presence row right away (otherwise timers keep firing in
/// the background and the player looks online forever).
class PresenceService extends GetxService with WidgetsBindingObserver {
  PresenceService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? Supabase.instance.client;

  Timer? _timer;
  String _busyMode = 'idle';
  bool _foreground = true;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = client.auth.onAuthStateChange.listen((state) {
      if (state.session != null) {
        start();
      } else {
        stop();
      }
    });
    if (client.auth.currentSession != null) {
      start();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        if (client.auth.currentSession != null) {
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
      await client.rpc<dynamic>(
        'heartbeat_presence',
        params: {'p_busy_mode': _busyMode},
      );
    } catch (_) {
      // Presence is best-effort.
    }
  }

  Future<void> _leave() async {
    if (client.auth.currentSession == null) {
      return;
    }
    try {
      await client.rpc<dynamic>('leave_presence');
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
