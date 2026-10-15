import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import 'convex_gateway.dart';

/// One-time move of a player's Supabase-era account onto their Firebase
/// identity, using the session the previous app version left on the
/// device. The backend verifies the session with the old GoTrue
/// (`account:claimLegacy`) and re-points the imported profile — rating,
/// points and history included — to the caller.
///
/// Remove (with supabase_flutter) once the handoff window closes.
class LegacyAccountHandoff {
  LegacyAccountHandoff({
    GoTrueClient? Function()? legacyAuth,
    Future<SharedPreferences> Function()? preferences,
  }) : _legacyAuth = legacyAuth ?? _defaultLegacyAuth,
       _preferences = preferences ?? SharedPreferences.getInstance;

  static const String _doneKey = 'legacy_supabase_claim_done';

  final GoTrueClient? Function() _legacyAuth;
  final Future<SharedPreferences> Function() _preferences;

  static GoTrueClient? _defaultLegacyAuth() {
    try {
      return Supabase.instance.client.auth;
    } catch (_) {
      return null; // Supabase not initialised (tests, fresh installs).
    }
  }

  Session? get _session => _legacyAuth()?.currentSession;

  /// A guest from the Supabase era: the app can sign them in anonymously
  /// and claim their profile without any prompt.
  bool get hasAnonymousLegacySession => _session?.user.isAnonymous ?? false;

  bool get hasLegacySession => _session != null;

  Future<bool> _isDone() async {
    try {
      return (await _preferences()).getBool(_doneKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _finish() async {
    try {
      await (await _preferences()).setBool(_doneKey, true);
      await _legacyAuth()?.signOut(scope: SignOutScope.local);
    } catch (_) {}
  }

  /// Claims the legacy profile for the identity [gateway] is authenticated
  /// as. Returns true when the caller's profile changed. Safe to call on
  /// every sign-in: it runs until it reaches a definitive answer.
  Future<bool> tryClaim(ConvexGateway gateway) async {
    final auth = _legacyAuth();
    if (auth == null || auth.currentSession == null || await _isDone()) {
      return false;
    }
    try {
      var session = auth.currentSession!;
      if (session.isExpired) {
        session = (await auth.refreshSession()).session ?? session;
      }
      final result = asRow(
        await gateway.action('account:claimLegacy', {
          'supabaseAccessToken': session.accessToken,
        }),
      );
      final status = result['status'] as String?;
      debugPrint('legacy account handoff: $status');
      if (status == 'unavailable') {
        return false; // Backend not configured / old stack down: retry later.
      }
      await _finish();
      return status == 'claimed';
    } on AuthException catch (error) {
      // The refresh token is dead (account deleted, revoked): nothing to
      // claim with any more.
      debugPrint('legacy account handoff: ${error.message}');
      await _finish();
      return false;
    } catch (error) {
      debugPrint('legacy account handoff deferred: $error');
      return false;
    }
  }
}
