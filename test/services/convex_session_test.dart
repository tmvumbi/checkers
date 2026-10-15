import 'dart:async';

import 'package:checkers/services/convex/convex_session.dart';
import 'package:checkers/services/convex/legacy_account_handoff.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_convex_gateway.dart';

class _Firebase extends Mock implements fb.FirebaseAuth {}

class _User extends Mock implements fb.User {}

class _Legacy extends Mock implements LegacyAccountHandoff {}


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeConvexGateway convex;
  late _Firebase firebase;
  late _User user;
  late _Legacy legacy;
  late StreamController<fb.User?> authChanges;

  setUpAll(() => registerFallbackValue(FakeConvexGateway()));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    convex = FakeConvexGateway();
    firebase = _Firebase();
    user = _User();
    legacy = _Legacy();
    authChanges = StreamController<fb.User?>.broadcast();
    when(() => user.uid).thenReturn('firebase-1');
    when(() => user.isAnonymous).thenReturn(true);
    when(() => user.email).thenReturn(null);
    when(() => user.displayName).thenReturn(null);
    when(() => user.getIdToken(any())).thenAnswer((_) async => 'id-token');
    when(
      () => firebase.authStateChanges(),
    ).thenAnswer((_) => authChanges.stream);
    when(() => legacy.hasAnonymousLegacySession).thenReturn(false);
    when(() => legacy.tryClaim(any())).thenAnswer((_) async => false);
    convex.on('profiles:ensure', (_) => {'id': 'profile-1'});
  });

  tearDown(() => authChanges.close());

  ConvexSession newSession() =>
      ConvexSession(gateway: convex, firebaseAuth: firebase, legacy: legacy);

  test(
    'attach authenticates Convex, claims legacy data, then provisions',
    () async {
      when(() => firebase.currentUser).thenReturn(user);
      final session = newSession();
      final emitted = <String?>[];
      session.userChanges.listen((u) => emitted.add(u?.uid));

      final authUser = await session.attach(user);

      expect(authUser.uid, 'profile-1');
      expect(session.user?.uid, 'profile-1');
      expect(await convex.tokenFetcher!(forceRefresh: false), 'id-token');
      verify(() => legacy.tryClaim(convex)).called(1);
      expect(convex.callsTo('profiles:ensure').single, {'isAnonymous': true});
      await Future<void>.delayed(Duration.zero);
      expect(emitted, ['profile-1']);
    },
  );

  test(
    'start restores a cached player instantly and refreshes in background',
    () async {
      SharedPreferences.setMockInitialValues({
        'convex_profile_for_firebase-1': 'cached-profile',
      });
      when(() => firebase.currentUser).thenReturn(user);
      final ensure = Completer<dynamic>();
      convex.on('profiles:ensure', (_) => ensure.future);

      final session = newSession();
      await session.start();
      expect(session.user?.uid, 'cached-profile');

      ensure.complete({'id': 'profile-1'});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(session.user?.uid, 'profile-1');
    },
  );

  test('a Supabase-era guest is signed in anonymously at start', () async {
    when(() => firebase.currentUser).thenReturn(null);
    when(() => legacy.hasAnonymousLegacySession).thenReturn(true);
    final credential = _Credential(user);
    when(
      () => firebase.signInAnonymously(),
    ).thenAnswer((_) async => credential);

    final session = newSession();
    await session.start();

    verify(() => firebase.signInAnonymously()).called(1);
    expect(session.user?.uid, 'profile-1');
  });

  test('signing out of Firebase clears the session', () async {
    when(() => firebase.currentUser).thenReturn(user);
    final session = newSession();
    await session.start();
    expect(session.user, isNotNull);

    authChanges.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(session.user, isNull);
    expect(convex.tokenFetcher, isNull);
  });
}

class _Credential extends Fake implements fb.UserCredential {
  _Credential(this.user);

  @override
  final fb.User? user;
}
