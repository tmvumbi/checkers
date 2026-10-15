import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:get/get.dart';

import '../core/network/api_error.dart';
import '../core/network/api_result.dart';
import 'auth_service.dart';
import 'convex/convex_gateway.dart';
import 'convex/convex_session.dart';

abstract class AccountDeletionService {
  Future<ApiResult<void>> deleteCurrentAccount();
}

/// Deletes the player's backend data (`account:deleteMine`: resigns live
/// games, anonymises history, removes the avatar and personal rows), then
/// the Firebase user itself.
class ConvexAccountDeletionService implements AccountDeletionService {
  ConvexAccountDeletionService({
    ConvexGateway? gateway,
    AuthService? authService,
    ConvexSession? session,
    fb.FirebaseAuth? firebaseAuth,
  }) : _gatewayOverride = gateway,
       _authOverride = authService,
       _sessionOverride = session,
       _firebaseOverride = firebaseAuth;

  final ConvexGateway? _gatewayOverride;
  final AuthService? _authOverride;
  final ConvexSession? _sessionOverride;
  final fb.FirebaseAuth? _firebaseOverride;

  ConvexGateway get _convex => _gatewayOverride ?? Get.find<ConvexGateway>();
  AuthService get _auth => _authOverride ?? Get.find<AuthService>();
  ConvexSession get _session => _sessionOverride ?? Get.find<ConvexSession>();
  fb.FirebaseAuth get _firebase =>
      _firebaseOverride ?? fb.FirebaseAuth.instance;

  @override
  Future<ApiResult<void>> deleteCurrentAccount() async {
    if (_auth.currentUser == null) {
      return const Failure(
        ApiError(
          code: 'not-authenticated',
          message: 'Sign in before deleting your account.',
        ),
      );
    }
    final deleted = await guardConvex(() async {
      await _convex.mutation('account:deleteMine');
    });
    if (deleted is Failure<void>) {
      return deleted;
    }
    try {
      await _firebase.currentUser?.delete();
    } on fb.FirebaseAuthException {
      // e.g. requires-recent-login for an old Google session: the game data
      // is already gone, so just end the session.
      await _firebase.signOut();
    }
    await _session.detach();
    return const Success(null);
  }
}
