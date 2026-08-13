import 'package:checkers/core/network/api_result.dart';
import 'package:checkers/data/models/user_profile.dart';
import 'package:checkers/main.dart';
import 'package:checkers/services/analytics_service.dart';
import 'package:checkers/services/auth_service.dart';
import 'package:checkers/services/online_game_service.dart';
import 'package:checkers/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthService extends Mock implements AuthService {}

class MockProfileService extends Mock implements ProfileService {}

class MockOnlineGameService extends Mock implements OnlineGameService {}

class _TestBinding extends Bindings {
  _TestBinding(this.auth, this.profile, this.online);

  final AuthService auth;
  final ProfileService profile;
  final OnlineGameService online;

  @override
  void dependencies() {
    Get.put<AnalyticsService>(NoopAnalyticsService());
    Get.put<AuthService>(auth);
    Get.put<ProfileService>(profile);
    Get.put<OnlineGameService>(online);
  }
}

const _guestUser = AuthUser(uid: 'uid-1', isAnonymous: true);

void main() {
  late MockAuthService auth;
  late MockProfileService profile;
  late MockOnlineGameService online;

  setUp(() {
    auth = MockAuthService();
    profile = MockProfileService();
    online = MockOnlineGameService();
    when(() => online.fetchWatchableGames()).thenAnswer(
      (_) async => const Success([]),
    );
    when(() => online.fetchLeaderboard()).thenAnswer(
      (_) async => const Success([]),
    );
    when(() => auth.supportsAppleSignIn).thenReturn(false);
    when(() => auth.currentUser).thenReturn(_guestUser);
    when(() => auth.userChanges).thenAnswer((_) => const Stream.empty());
    when(() => profile.getProfile('uid-1')).thenAnswer(
      (_) async => const Success(
        UserProfile(uid: 'uid-1', nickname: 'Zola', rating: 1234),
      ),
    );
  });

  tearDown(Get.reset);

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      CheckersApp(
        initialBinding: _TestBinding(auth, profile, online),
        initialRoute: '/home',
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('play tab shows profile header with rating and buttons', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(find.text('Zola'), findsOneWidget);
    expect(find.byKey(const Key('home-profile-rating')), findsOneWidget);
    expect(find.text('1234'), findsOneWidget);
    expect(find.byKey(const Key('home-play-pc-button')), findsOneWidget);
    expect(find.byKey(const Key('home-play-people-button')), findsOneWidget);
    expect(find.byKey(const Key('home-how-to-play-button')), findsOneWidget);
  });

  testWidgets('bottom navigation switches tabs', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-tab-watch')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-play-pc-button')), findsNothing);

    await tester.tap(find.byKey(const Key('home-tab-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('more-log-out-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-tab-play')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-play-pc-button')), findsOneWidget);
  });

  testWidgets('anonymous log-out asks for confirmation then lands on landing',
      (tester) async {
    when(() => auth.signOut()).thenAnswer((_) async => const Success(null));

    await pumpHome(tester);
    await tester.tap(find.byKey(const Key('home-tab-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('more-log-out-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('more-log-out-confirm')), findsOneWidget);

    when(() => auth.currentUser).thenReturn(null);
    await tester.tap(find.byKey(const Key('more-log-out-confirm')));
    await tester.pumpAndSettle();

    verify(() => auth.signOut()).called(1);
    expect(find.byKey(const Key('landing-guest-button')), findsOneWidget);
  });
}
