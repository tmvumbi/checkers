import 'package:checkers/core/network/api_result.dart';
import 'package:checkers/services/account_deletion_service.dart';
import 'package:checkers/services/auth_service.dart';
import 'package:checkers/services/convex/convex_session.dart';
import 'package:dartvex/dartvex.dart' show ConvexException;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fake_convex_gateway.dart';

class _Auth extends Mock implements AuthService {}

class _Session extends Mock implements ConvexSession {}

class _Firebase extends Mock implements fb.FirebaseAuth {}

class _User extends Mock implements fb.User {}

void main() {
  late FakeConvexGateway convex;
  late _Auth auth;
  late _Session session;
  late _Firebase firebase;
  late _User user;
  late ConvexAccountDeletionService service;

  setUp(() {
    convex = FakeConvexGateway();
    auth = _Auth();
    session = _Session();
    firebase = _Firebase();
    user = _User();
    when(
      () => auth.currentUser,
    ).thenReturn(const AuthUser(uid: 'profile-1', isAnonymous: true));
    when(() => firebase.currentUser).thenReturn(user);
    when(() => user.delete()).thenAnswer((_) async {});
    when(() => firebase.signOut()).thenAnswer((_) async {});
    when(() => session.detach()).thenAnswer((_) async {});
    service = ConvexAccountDeletionService(
      gateway: convex,
      authService: auth,
      session: session,
      firebaseAuth: firebase,
    );
  });

  test('deletes backend data, then the Firebase user', () async {
    convex.on('account:deleteMine', (_) => null);
    expect(await service.deleteCurrentAccount(), isA<Success<void>>());
    expect(convex.callsTo('account:deleteMine'), hasLength(1));
    verify(() => user.delete()).called(1);
    verify(() => session.detach()).called(1);
  });

  test('a backend failure keeps the Firebase account for a retry', () async {
    convex.on(
      'account:deleteMine',
      (_) => throw const ConvexException('Server Error', data: 'busy'),
    );
    final result = await service.deleteCurrentAccount();
    expect((result as Failure<void>).error.code, 'busy');
    verifyNever(() => user.delete());
    verifyNever(() => session.detach());
  });

  test('an old Google session that needs re-login is signed out', () async {
    convex.on('account:deleteMine', (_) => null);
    when(
      () => user.delete(),
    ).thenThrow(fb.FirebaseAuthException(code: 'requires-recent-login'));
    expect(await service.deleteCurrentAccount(), isA<Success<void>>());
    verify(() => firebase.signOut()).called(1);
    verify(() => session.detach()).called(1);
  });

  test('no session: nothing is deleted', () async {
    when(() => auth.currentUser).thenReturn(null);
    final result = await service.deleteCurrentAccount();
    expect((result as Failure<void>).error.code, 'not-authenticated');
    expect(convex.calls, isEmpty);
  });
}
