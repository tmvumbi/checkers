import 'dart:async';

import 'package:checkers/core/network/api_result.dart';
import 'package:checkers/core/network/api_error.dart';
import 'package:checkers/services/account_deletion_service.dart';
import 'package:checkers/data/models/online_game.dart';
import 'package:checkers/data/models/user_profile.dart';
import 'package:checkers/engine/checkers_engine.dart';
import 'package:checkers/engine/rules_config.dart';
import 'package:checkers/main.dart';
import 'package:checkers/modules/game_board/models/game_board_arguments.dart';
import 'package:checkers/modules/home/controller/home_controller.dart';
import 'package:checkers/services/analytics_service.dart';
import 'package:checkers/services/auth_service.dart';
import 'package:checkers/services/online_game_service.dart';
import 'package:checkers/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthService extends Mock implements AuthService {}

class MockAccountDeletionService extends Mock
    implements AccountDeletionService {}

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
    when(() => profile.watchProfile(any())).thenAnswer(
      (call) => Stream.fromFuture(
        profile.getProfile(call.positionalArguments.first as String),
      ).map((result) => result.when(success: (p) => p, failure: (_) => null)),
    );
    online = MockOnlineGameService();
    when(
      () => online.fetchWatchableGames(
        offset: any(named: 'offset'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => const Success([]));
    when(
      () => online.fetchRecentGames(
        search: any(named: 'search'),
        mine: any(named: 'mine'),
        offset: any(named: 'offset'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => const Success([]));
    when(
      () => online.fetchLeaderboard(),
    ).thenAnswer((_) async => const Success([]));
    when(
      () => online.fetchPointsLeaderboard(),
    ).thenAnswer((_) async => const Success([]));
    when(
      () => online.fetchPointRules(),
    ).thenAnswer((_) async => const Success(PointRules()));
    when(
      () => online.fetchMyActiveGame(),
    ).thenAnswer((_) async => const Success(null));
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

  testWidgets('profile header follows fresh values after a cached result', (
    tester,
  ) async {
    final updates = StreamController<UserProfile?>();
    when(() => profile.watchProfile('uid-1')).thenAnswer((_) => updates.stream);
    await pumpHome(tester);
    updates.add(const UserProfile(uid: 'uid-1', nickname: ''));
    await tester.pump();
    expect(find.text('Saved player'), findsNothing);
    updates.add(const UserProfile(uid: 'uid-1', nickname: 'Saved player'));
    await tester.pump();
    expect(find.text('Saved player'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
    expect(updates.hasListener, isFalse);
    unawaited(updates.close());
    await tester.pump();
  });

  testWidgets(
    'failed deletion keeps session and home; successful retry signs out',
    (tester) async {
      final deletion = MockAccountDeletionService();
      Get.put<AccountDeletionService>(deletion);
      when(() => deletion.deleteCurrentAccount()).thenAnswer(
        (_) async =>
            const Failure(ApiError(code: 'delete-failed', message: 'Offline')),
      );
      await pumpHome(tester);
      final controller = Get.find<HomeController>();
      expect(await controller.deleteAccount(), isFalse);
      verifyNever(() => auth.signOut());
      expect(Get.currentRoute, '/home');

      when(
        () => deletion.deleteCurrentAccount(),
      ).thenAnswer((_) async => const Success(null));
      when(() => auth.signOut()).thenAnswer((_) async {
        when(() => auth.currentUser).thenReturn(null);
        return const Success(null);
      });
      expect(await controller.deleteAccount(), isTrue);
      await tester.pumpAndSettle();
      verify(() => auth.signOut()).called(1);
      expect(find.byKey(const Key('landing-guest-button')), findsOneWidget);
    },
  );

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

  testWidgets('no resume banner when there is no game in progress', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(find.byKey(const Key('home-resume-game-button')), findsNothing);
  });

  testWidgets('a game left in progress offers a way back into it', (
    tester,
  ) async {
    when(() => online.fetchMyActiveGame()).thenAnswer(
      (_) async => Success(
        ResumableGame(
          gameId: 'game-42',
          rules: RulesConfig.international,
          humanColor: PieceColor.black,
          opponentNickname: 'Marion',
          myTurn: true,
        ),
      ),
    );
    await pumpHome(tester);

    expect(find.byKey(const Key('home-resume-game-button')), findsOneWidget);
    expect(find.textContaining('Marion'), findsOneWidget);
    // The clock keeps running while the app is closed, so say whose move it is.
    expect(find.textContaining('Your turn'), findsOneWidget);
  });

  test('resuming re-enters as a player, not a spectator', () async {
    when(() => online.fetchMyActiveGame()).thenAnswer(
      (_) async => Success(
        ResumableGame(
          gameId: 'game-42',
          rules: RulesConfig.international,
          humanColor: PieceColor.black,
          opponentNickname: 'Marion',
          myTurn: true,
        ),
      ),
    );
    final controller = HomeController(
      authService: auth,
      profileService: profile,
      analyticsService: NoopAnalyticsService(),
      onlineGameService: online,
    );

    await controller.refreshActiveGame();
    expect(controller.activeGame.value?.gameId, 'game-42');

    final args = controller.resumeArguments()!;
    expect(args.mode, GameBoardMode.online);
    expect(args.gameId, 'game-42');
    expect(args.humanColor, PieceColor.black);
    expect(args.rules.boardSize, 10);
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

  testWidgets('recent game cards show when the game was completed', (
    tester,
  ) async {
    final completedAt = DateTime.now().toUtc().subtract(
      const Duration(minutes: 5, seconds: 10),
    );
    when(
      () => online.fetchRecentGames(
        search: any(named: 'search'),
        mine: any(named: 'mine'),
        offset: any(named: 'offset'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer(
      (_) async => Success([
        OnlineGameSnapshot(
          id: 'recent-1',
          status: 'finished',
          rules: RulesConfig.american,
          ply: 12,
          sideToMove: PieceColor.white,
          board: const [],
          whiteBankMs: 1000,
          blackBankMs: 1000,
          result: 'whiteWin',
          finishedAt: completedAt,
          players: const [
            OnlineGamePlayer(
              uid: 'white',
              seat: 0,
              nickname: 'White player',
              color: PieceColor.white,
            ),
            OnlineGamePlayer(
              uid: 'black',
              seat: 1,
              nickname: 'Black player',
              color: PieceColor.black,
            ),
          ],
        ),
      ]),
    );

    await pumpHome(tester);
    await tester.tap(find.byKey(const Key('home-tab-watch')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('recent-game-recent-1-completed-at')),
      findsOneWidget,
    );
    expect(find.text('5 min ago'), findsOneWidget);
  });

  testWidgets('Top 30 switches between Elo and Points and explains awards', (
    tester,
  ) async {
    when(() => online.fetchLeaderboard()).thenAnswer(
      (_) async => const Success([
        LeaderboardPlayer(
          uid: 'elo-1',
          nickname: 'Elo leader',
          rating: 1800,
          ratedGames: 20,
          wins: 12,
          losses: 6,
          draws: 2,
        ),
      ]),
    );
    when(() => online.fetchPointsLeaderboard()).thenAnswer(
      (_) async => const Success([
        LeaderboardPlayer(
          uid: 'points-1',
          nickname: 'Points leader',
          rating: 1500,
          points: 16,
          ratedGames: 3,
          wins: 2,
          losses: 1,
          draws: 0,
        ),
      ]),
    );

    await pumpHome(tester);
    await tester.tap(find.byKey(const Key('home-tab-leaderboard')));
    await tester.pumpAndSettle();

    expect(find.text('Elo Score'), findsOneWidget);
    expect(find.text('Elo leader'), findsOneWidget);

    await tester.tap(find.byKey(const Key('leaderboard-points-tab')));
    await tester.pumpAndSettle();

    expect(find.text('Points leader'), findsOneWidget);
    expect(find.text('16 pts'), findsOneWidget);
    expect(find.byKey(const Key('points-info-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('points-info-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('points-info-modal')), findsOneWidget);
    expect(find.textContaining('Easy 1 pt'), findsOneWidget);
    expect(find.textContaining('1 point(s) per participant'), findsOneWidget);
  });

  test('point-rule payload uses configured values', () {
    final rules = PointRules.fromJson({
      'pc_easy_win': 2,
      'pc_medium_win': 6,
      'pc_hard_win': 12,
      'tournament_per_participant': 3,
      'tournament_bonus': 4,
    });

    expect(rules.pcEasyWin, 2);
    expect(rules.pcMediumWin, 6);
    expect(rules.pcHardWin, 12);
    expect(rules.tournamentPerParticipant, 3);
    expect(rules.tournamentBonus, 4);
  });

  testWidgets('anonymous log-out asks for confirmation then lands on landing', (
    tester,
  ) async {
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
