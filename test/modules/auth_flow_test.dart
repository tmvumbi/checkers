import 'package:checkers/core/network/api_error.dart';
import 'package:checkers/core/network/api_result.dart';
import 'package:checkers/data/models/user_profile.dart';
import 'package:checkers/main.dart';
import 'package:checkers/services/analytics_service.dart';
import 'package:checkers/services/auth_service.dart';
import 'package:checkers/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthService extends Mock implements AuthService {}

class MockProfileService extends Mock implements ProfileService {}

class _TestBinding extends Bindings {
  _TestBinding(this.auth, this.profile);

  final AuthService auth;
  final ProfileService profile;

  @override
  void dependencies() {
    Get.put<AnalyticsService>(NoopAnalyticsService());
    Get.put<AuthService>(auth);
    Get.put<ProfileService>(profile);
  }
}

const _guestUser = AuthUser(uid: 'uid-1', isAnonymous: true);

void main() {
  late MockAuthService auth;
  late MockProfileService profile;

  setUpAll(() {
    registerFallbackValue(const UserProfile(uid: 'fallback', nickname: ''));
  });

  setUp(() {
    auth = MockAuthService();
    profile = MockProfileService();
    when(() => auth.supportsAppleSignIn).thenReturn(false);
    when(() => auth.currentUser).thenReturn(null);
    when(() => auth.userChanges).thenAnswer((_) => const Stream.empty());
  });

  tearDown(Get.reset);

  Future<void> pumpApp(WidgetTester tester, {String initialRoute = '/'}) async {
    await tester.pumpWidget(
      CheckersApp(
        initialBinding: _TestBinding(auth, profile),
        initialRoute: initialRoute,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('guest sign-in without profile routes to edit profile, '
      'saving routes home', (tester) async {
    when(
      () => auth.signInAnonymously(),
    ).thenAnswer((_) async => const Success(_guestUser));
    when(
      () => profile.getProfile('uid-1'),
    ).thenAnswer((_) async => const Success(null));

    await pumpApp(tester);
    expect(find.byKey(const Key('landing-guest-button')), findsOneWidget);
    expect(find.byKey(const Key('landing-apple-button')), findsNothing);

    // After the guest taps through, the auth session exists.
    when(() => auth.currentUser).thenReturn(_guestUser);
    await tester.tap(find.byKey(const Key('landing-guest-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('edit-profile-nickname')), findsOneWidget);

    const saved = UserProfile(uid: 'uid-1', nickname: 'Marie');
    when(
      () => profile.upsertProfile(any(that: isA<UserProfile>())),
    ).thenAnswer((_) async => const Success(saved));
    when(
      () => profile.getProfile('uid-1'),
    ).thenAnswer((_) async => const Success(saved));

    await tester.enterText(
      find.byKey(const Key('edit-profile-nickname')),
      'Marie',
    );
    await tester.tap(find.byKey(const Key('edit-profile-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-tab-play')), findsOneWidget);
    expect(find.text('Marie'), findsOneWidget);
  });

  testWidgets('guest sign-in with existing profile routes straight home', (
    tester,
  ) async {
    when(
      () => auth.signInAnonymously(),
    ).thenAnswer((_) async => const Success(_guestUser));
    when(() => profile.getProfile('uid-1')).thenAnswer(
      (_) async => const Success(UserProfile(uid: 'uid-1', nickname: 'Zola')),
    );

    await pumpApp(tester);
    when(() => auth.currentUser).thenReturn(_guestUser);
    await tester.tap(find.byKey(const Key('landing-guest-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-tab-play')), findsOneWidget);
    expect(find.text('Zola'), findsOneWidget);
  });

  testWidgets('empty nickname shows validation error and stays', (
    tester,
  ) async {
    when(() => auth.currentUser).thenReturn(_guestUser);
    when(
      () => profile.getProfile('uid-1'),
    ).thenAnswer((_) async => const Success(null));

    await pumpApp(tester, initialRoute: '/edit-profile');
    await tester.tap(find.byKey(const Key('edit-profile-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('edit-profile-nickname')), findsOneWidget);
    verifyNever(() => profile.upsertProfile(any(that: isA<UserProfile>())));
  });

  testWidgets('failed sign-in stays on landing', (tester) async {
    when(() => auth.signInAnonymously()).thenAnswer(
      (_) async =>
          const Failure(ApiError(code: 'auth-error', message: 'nope')),
    );

    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('landing-guest-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('landing-guest-button')), findsOneWidget);

    // Let the failure snackbar's auto-dismiss timer elapse before teardown.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('existing session on landing goes straight home', (tester) async {
    when(() => auth.currentUser).thenReturn(_guestUser);
    when(() => profile.getProfile('uid-1')).thenAnswer(
      (_) async => const Success(UserProfile(uid: 'uid-1', nickname: 'Zola')),
    );

    await pumpApp(tester);
    expect(find.byKey(const Key('home-tab-play')), findsOneWidget);
  });
}
