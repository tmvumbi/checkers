import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../core/config/google_auth_config.dart';
import '../core/network/api_error.dart';
import '../core/network/api_result.dart';
import 'convex/convex_gateway.dart';
import 'convex/convex_session.dart';

/// Authenticated user snapshot, decoupled from the backend SDK.
class AuthUser {
  const AuthUser({
    required this.uid,
    required this.isAnonymous,
    this.email,
    this.displayName,
  });

  final String uid;
  final bool isAnonymous;
  final String? email;
  final String? displayName;
}

abstract class AuthService {
  AuthUser? get currentUser;
  Stream<AuthUser?> get userChanges;

  Future<ApiResult<AuthUser>> signInAnonymously();
  Future<ApiResult<AuthUser>> signInWithGoogle();
  Future<ApiResult<AuthUser>> signInWithApple();

  /// Upgrades the current anonymous session to a permanent Google identity.
  Future<ApiResult<AuthUser>> linkWithGoogle();

  Future<ApiResult<void>> signOut();

  bool get supportsAppleSignIn;
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({
    ConvexSession? session,
    fb.FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  }) : _sessionOverride = session,
       _firebaseOverride = firebaseAuth,
       _googleOverride = googleSignIn;

  final ConvexSession? _sessionOverride;
  final fb.FirebaseAuth? _firebaseOverride;
  final GoogleSignIn? _googleOverride;

  ConvexSession get _session => _sessionOverride ?? Get.find<ConvexSession>();
  fb.FirebaseAuth get _firebase =>
      _firebaseOverride ?? fb.FirebaseAuth.instance;
  GoogleSignIn get _google => _googleOverride ?? GoogleSignIn.instance;

  @override
  bool get supportsAppleSignIn =>
      !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  @override
  AuthUser? get currentUser => _session.user;

  @override
  Stream<AuthUser?> get userChanges => _session.userChanges;

  Future<AuthUser> _attach(fb.UserCredential credential) async {
    final user = credential.user;
    if (user == null) {
      throw fb.FirebaseAuthException(code: 'no-user-in-response');
    }
    return _session.attach(user);
  }

  @override
  Future<ApiResult<AuthUser>> signInAnonymously() {
    return _guard(() async => _attach(await _firebase.signInAnonymously()));
  }

  @override
  Future<ApiResult<AuthUser>> signInWithGoogle() {
    return _guard(() async {
      final credential = await _googleCredential();
      return _attach(await _firebase.signInWithCredential(credential));
    });
  }

  /// Upgrades a guest to Google, keeping their Firebase uid (and so their
  /// profile). If that Google account already has a Firebase user, the
  /// player is switched to it instead.
  @override
  Future<ApiResult<AuthUser>> linkWithGoogle() {
    return _guard(() async {
      final credential = await _googleCredential();
      final current = _firebase.currentUser;
      if (current == null) {
        return _attach(await _firebase.signInWithCredential(credential));
      }
      try {
        await current.linkWithCredential(credential);
        return _session.refresh();
      } on fb.FirebaseAuthException catch (error) {
        if (error.code != 'credential-already-in-use') rethrow;
        return _attach(
          await _firebase.signInWithCredential(error.credential ?? credential),
        );
      }
    });
  }

  Future<fb.AuthCredential> _googleCredential() async {
    // Apple platforms need their own OAuth client id; Android derives it
    // from the signing certificate. Firebase accepts ID tokens minted for
    // any OAuth client of the checkers-club project.
    await _google.initialize(
      clientId: !kIsWeb && (Platform.isIOS || Platform.isMacOS)
          ? GoogleAuthConfig.iosClientId
          : null,
      serverClientId: GoogleAuthConfig.serverClientId,
    );
    final account = await _google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw fb.FirebaseAuthException(code: 'missing-google-id-token');
    }
    return fb.GoogleAuthProvider.credential(idToken: idToken);
  }

  @override
  Future<ApiResult<AuthUser>> signInWithApple() {
    return _guard(() async {
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
      final apple = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      final idToken = apple.identityToken;
      if (idToken == null) {
        throw fb.FirebaseAuthException(code: 'missing-apple-identity-token');
      }
      final credential = fb.OAuthProvider('apple.com').credential(
        idToken: idToken,
        rawNonce: rawNonce,
        accessToken: apple.authorizationCode,
      );
      return _attach(await _firebase.signInWithCredential(credential));
    });
  }

  @override
  Future<ApiResult<void>> signOut() {
    return _guard(() async {
      await _firebase.signOut();
      try {
        await _google.signOut();
      } catch (_) {}
      await _session.detach();
    });
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  Future<ApiResult<T>> _guard<T>(Future<T> Function() action) async {
    try {
      return Success(await action());
    } on fb.FirebaseAuthException catch (error) {
      return Failure(ApiError(code: error.code, message: error.message ?? ''));
    } on GoogleSignInException catch (error) {
      final cancelled = error.code == GoogleSignInExceptionCode.canceled;
      return Failure(
        ApiError(
          code: cancelled ? 'google-sign-in-cancelled' : 'google-sign-in-error',
          message: error.description ?? 'Google sign-in failed',
        ),
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      final cancelled = error.code == AuthorizationErrorCode.canceled;
      return Failure(
        ApiError(
          code: cancelled ? 'apple-sign-in-cancelled' : 'apple-sign-in-error',
          message: error.message,
        ),
      );
    } catch (error) {
      return Failure(
        ApiError(code: convexErrorCode(error), message: error.toString()),
      );
    }
  }
}
