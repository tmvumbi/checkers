import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth_service.dart';
import 'convex_gateway.dart';
import 'legacy_account_handoff.dart';

/// Binds the Firebase sign-in to the Convex backend: forwards ID tokens,
/// provisions the player's profile (`profiles:ensure`) and exposes the
/// resulting [AuthUser], whose `uid` is the Convex profile id used across
/// all game data.
///
/// The Firebase uid → profile id mapping is cached on the device so a
/// returning player is recognised synchronously at start-up, even offline.
class ConvexSession {
  ConvexSession({
    required this.gateway,
    fb.FirebaseAuth? firebaseAuth,
    LegacyAccountHandoff? legacy,
    Future<SharedPreferences> Function()? preferences,
  }) : _firebaseOverride = firebaseAuth,
       _legacy = legacy ?? LegacyAccountHandoff(),
       _preferences = preferences ?? SharedPreferences.getInstance;

  final ConvexGateway gateway;
  final fb.FirebaseAuth? _firebaseOverride;
  final LegacyAccountHandoff _legacy;
  final Future<SharedPreferences> Function() _preferences;

  fb.FirebaseAuth get firebase => _firebaseOverride ?? fb.FirebaseAuth.instance;

  final StreamController<AuthUser?> _changes =
      StreamController<AuthUser?>.broadcast();
  AuthUser? _user;
  String? _attachedFirebaseUid;
  final Map<String, Future<AuthUser>> _attaching = {};
  StreamSubscription<fb.User?>? _firebaseSubscription;

  static const String _cachePrefix = 'convex_profile_for_';

  AuthUser? get user => _user;
  Stream<AuthUser?> get userChanges => _changes.stream;

  void _emit(AuthUser? user) {
    _user = user;
    _changes.add(user);
  }

  AuthUser _authUser(fb.User user, String profileId) => AuthUser(
    uid: profileId,
    isAnonymous: user.isAnonymous,
    email: user.email,
    displayName: user.displayName,
  );

  /// Restores the session at app start. Waits at most [timeout] for the
  /// backend when nothing is cached.
  Future<void> start({Duration timeout = const Duration(seconds: 6)}) async {
    var current = firebase.currentUser;
    if (current == null && _legacy.hasAnonymousLegacySession) {
      try {
        current = (await firebase.signInAnonymously()).user;
      } catch (error) {
        debugPrint('anonymous sign-in for legacy guest failed: $error');
      }
    }
    if (current != null) {
      final cached = await _cachedProfileId(current.uid);
      if (cached != null) {
        _attachedFirebaseUid = current.uid;
        _emit(_authUser(current, cached));
        unawaited(attach(current).then((_) {}, onError: (_) {}));
      } else {
        try {
          await attach(current).timeout(timeout);
        } catch (error) {
          debugPrint('convex session restore deferred: $error');
        }
      }
    }
    _firebaseSubscription = firebase.authStateChanges().listen((user) {
      if (user == null) {
        if (_user != null) unawaited(detach());
      } else if (user.uid != _attachedFirebaseUid || _user == null) {
        unawaited(attach(user).then((_) {}, onError: (_) {}));
      }
    });
  }

  /// Authenticates Convex as [user] and provisions their profile.
  Future<AuthUser> attach(fb.User user) {
    // The callback must not return the removed future: whenComplete would
    // then wait on itself.
    return _attaching[user.uid] ??= _attach(user).whenComplete(() {
      _attaching.remove(user.uid);
    });
  }

  Future<AuthUser> _attach(fb.User user) async {
    await gateway.setAuth(({required bool forceRefresh}) async {
      return firebase.currentUser?.getIdToken(forceRefresh);
    });
    await _legacy.tryClaim(gateway);
    final profile = asRow(
      await gateway.mutation('profiles:ensure', {
        'isAnonymous': user.isAnonymous,
      }),
    );
    final profileId = profile['id'] as String;
    _attachedFirebaseUid = user.uid;
    await _cacheProfileId(user.uid, profileId);
    final authUser = _authUser(user, profileId);
    _emit(authUser);
    return authUser;
  }

  /// Re-reads the profile after the Firebase user changed in place
  /// (e.g. a guest linked Google).
  Future<AuthUser> refresh() async {
    final current = firebase.currentUser;
    if (current == null) throw StateError('not signed in');
    await current.reload();
    return attach(firebase.currentUser ?? current);
  }

  Future<void> detach() async {
    _attachedFirebaseUid = null;
    try {
      await gateway.setAuth(null);
    } catch (_) {}
    if (_user != null) _emit(null);
  }

  Future<String?> _cachedProfileId(String firebaseUid) async {
    try {
      return (await _preferences()).getString('$_cachePrefix$firebaseUid');
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheProfileId(String firebaseUid, String profileId) async {
    try {
      await (await _preferences()).setString(
        '$_cachePrefix$firebaseUid',
        profileId,
      );
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _firebaseSubscription?.cancel();
    await _changes.close();
  }
}
