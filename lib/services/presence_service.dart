import 'dart:async';

import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps this player's row in `player_presence` fresh while signed in —
/// powers the invite-a-friend directory (kopo's availablePlayers).
class PresenceService extends GetxService {
  PresenceService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? Supabase.instance.client;

  Timer? _timer;
  String _busyMode = 'idle';
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void onInit() {
    super.onInit();
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

  void start() {
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

  @override
  void onClose() {
    _authSubscription?.cancel();
    stop();
    super.onClose();
  }
}
