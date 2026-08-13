import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/api_error.dart';
import '../core/network/api_result.dart';

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

class SupabaseAuthService implements AuthService {
  SupabaseAuthService({GoTrueClient? client})
    : _client = client ?? Supabase.instance.client.auth;

  final GoTrueClient _client;

  @override
  bool get supportsAppleSignIn =>
      !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  @override
  AuthUser? get currentUser => _mapUser(_client.currentUser);

  @override
  Stream<AuthUser?> get userChanges =>
      _client.onAuthStateChange.map((state) => _mapUser(state.session?.user));

  AuthUser? _mapUser(User? user) {
    if (user == null) {
      return null;
    }
    return AuthUser(
      uid: user.id,
      isAnonymous: user.isAnonymous,
      email: user.email,
      displayName: user.userMetadata?['full_name'] as String?,
    );
  }

  @override
  Future<ApiResult<AuthUser>> signInAnonymously() {
    return _guard(() async {
      final response = await _client.signInAnonymously();
      return _requireUser(response.user);
    });
  }

  @override
  Future<ApiResult<AuthUser>> signInWithGoogle() {
    return _guard(() async {
      final idToken = await _googleIdToken();
      final response = await _client.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
      return _requireUser(response.user);
    });
  }

  @override
  Future<ApiResult<AuthUser>> linkWithGoogle() {
    return _guard(() async {
      final idToken = await _googleIdToken();
      final response = await _client.updateUser(
        UserAttributes(),
      ).then((_) async {
        // Supabase links an anonymous user to an identity by signing in with
        // the id token while a session exists; GoTrue merges when the
        // anonymous flag is set.
        return _client.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
        );
      });
      return _requireUser(response.user);
    });
  }

  Future<String> _googleIdToken() async {
    final googleSignIn = GoogleSignIn.instance;
    await googleSignIn.initialize();
    final account = await googleSignIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('missing-google-id-token');
    }
    return idToken;
  }

  @override
  Future<ApiResult<AuthUser>> signInWithApple() {
    return _guard(() async {
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const AuthException('missing-apple-identity-token');
      }
      final response = await _client.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
      return _requireUser(response.user);
    });
  }

  @override
  Future<ApiResult<void>> signOut() {
    return _guard(() => _client.signOut());
  }

  AuthUser _requireUser(User? user) {
    final mapped = _mapUser(user);
    if (mapped == null) {
      throw const AuthException('no-user-in-response');
    }
    return mapped;
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
    } on AuthException catch (error) {
      return Failure(
        ApiError(code: error.code ?? 'auth-error', message: error.message),
      );
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
      return Failure(ApiError(code: 'unknown', message: error.toString()));
    }
  }
}
