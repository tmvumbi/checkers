import 'package:checkers/core/network/api_result.dart';
import 'package:checkers/data/models/online_game.dart';
import 'package:checkers/data/models/tournament.dart';
import 'package:checkers/engine/checkers_engine.dart';
import 'package:checkers/engine/rules_config.dart';
import 'package:checkers/modules/game_board/models/game_board_arguments.dart';
import 'package:checkers/modules/tournament/controller/tournament_controller.dart';
import 'package:checkers/routes/app_routes.dart';
import 'package:checkers/services/analytics_service.dart';
import 'package:checkers/services/auth_service.dart';
import 'package:checkers/services/online_game_service.dart';
import 'package:checkers/services/tournament_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';

class MockTournamentService extends Mock implements TournamentService {}

class MockOnlineGameService extends Mock implements OnlineGameService {}

class MockAuthService extends Mock implements AuthService {}

const _me = AuthUser(uid: 'me', isAnonymous: true);

TournamentDetail _detail({
  required String stage,
  String? gameId,
  String matchStatus = 'playing',
  String tournamentStatus = 'knockout',
}) {
  return TournamentDetail(
    summary: TournamentSummary(
      id: 't1',
      number: 7,
      status: tournamentStatus,
      stage: stage,
      participantCount: 4,
      createdAt: DateTime(2026, 8, 22),
    ),
    players: const [],
    matches: [
      TournamentMatch(
        id: 'm-$stage',
        stage: stage,
        matchIndex: 0,
        p1Uid: 'me',
        p2Uid: 'them',
        status: matchStatus,
        gameId: gameId,
      ),
    ],
  );
}

OnlineGameSnapshot _snapshot(String gameId) {
  return OnlineGameSnapshot(
    id: gameId,
    status: 'playing',
    rules: RulesConfig.international,
    ply: 0,
    sideToMove: PieceColor.white,
    board: const [],
    whiteBankMs: 120000,
    blackBankMs: 120000,
    players: const [
      OnlineGamePlayer(
        seat: 0,
        uid: 'me',
        nickname: 'Me',
        color: PieceColor.black,
      ),
    ],
  );
}

void main() {
  late MockTournamentService tournaments;
  late MockOnlineGameService online;
  late MockAuthService auth;

  setUp(() {
    tournaments = MockTournamentService();
    online = MockOnlineGameService();
    auth = MockAuthService();
    when(() => auth.currentUser).thenReturn(_me);
    when(() => tournaments.watchMatches(any())).thenAnswer(
      (_) => const Stream<List<TournamentMatch>>.empty(),
    );
    when(() => online.fetchGame(any())).thenAnswer(
      (invocation) async =>
          Success(_snapshot(invocation.positionalArguments.first as String)),
    );
  });

  tearDown(Get.reset);

  /// The real board needs the whole app binding, so the routes are stubbed:
  /// what matters here is which route is pushed, and with what arguments.
  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: '/bracket',
        getPages: [
          GetPage(name: '/bracket', page: () => const SizedBox.shrink()),
          GetPage(
            name: AppRoutes.gameBoard,
            page: () => const SizedBox(key: Key('stub-board')),
          ),
          GetPage(
            name: AppRoutes.tournament,
            page: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  TournamentController build() {
    return TournamentController(
      tournamentId: 't1',
      tournamentService: tournaments,
      onlineGameService: online,
      authService: auth,
      analyticsService: NoopAnalyticsService(),
    );
  }

  void detailIs(TournamentDetail value) {
    when(() => tournaments.fetchTournamentDetail('t1')).thenAnswer(
      (_) async => Success(value),
    );
  }

  testWidgets('a paired match is opened without waiting for a tap', (
    tester,
  ) async {
    await pumpShell(tester);
    detailIs(_detail(stage: 'sf', gameId: 'game-sf'));
    final controller = build();

    await controller.refreshDetail();
    await tester.pumpAndSettle();

    expect(controller.myMatchReady.value, isTrue);
    // Opened on its own — that game's clock is already running.
    expect(find.byKey(const Key('stub-board')), findsOneWidget);
    verify(() => online.fetchGame('game-sf')).called(1);
  });

  testWidgets('the board is entered as a player, carrying the tournament', (
    tester,
  ) async {
    await pumpShell(tester);
    detailIs(_detail(stage: 'sf', gameId: 'game-sf'));
    final controller = build();

    await controller.refreshDetail();
    await tester.pumpAndSettle();

    final args = Get.arguments as GameBoardArguments;
    expect(args.mode, GameBoardMode.online);
    expect(args.gameId, 'game-sf');
    expect(args.humanColor, PieceColor.black);
    // Without this the board offers a rematch and strands the player.
    expect(args.tournamentId, 't1');
    expect(args.isTournamentMatch, isTrue);
  });

  testWidgets('backing out of a match does not drag the player back in', (
    tester,
  ) async {
    await pumpShell(tester);
    detailIs(_detail(stage: 'sf', gameId: 'game-sf'));
    final controller = build();

    await controller.refreshDetail();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stub-board')), findsOneWidget);

    // The player leaves the game deliberately; the bracket re-polls.
    Get.back<void>();
    await tester.pumpAndSettle();
    await controller.refreshDetail();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stub-board')), findsNothing);
    verify(() => online.fetchGame('game-sf')).called(1);
    // The button stays, for deliberate re-entry.
    expect(controller.myMatchReady.value, isTrue);
  });

  testWidgets('the next round is opened as soon as it is paired', (
    tester,
  ) async {
    await pumpShell(tester);
    detailIs(_detail(stage: 'sf', gameId: 'game-sf'));
    final controller = build();

    await controller.refreshDetail();
    await tester.pumpAndSettle();
    verify(() => online.fetchGame('game-sf')).called(1);

    // Semifinal ends; the server trigger pairs the final immediately.
    detailIs(_detail(stage: 'f', gameId: 'game-final'));
    Get.back<void>();
    await tester.pumpAndSettle();

    verify(() => online.fetchGame('game-final')).called(1);
    expect((Get.arguments as GameBoardArguments).gameId, 'game-final');
  });

  testWidgets('a match with no game yet is not opened', (tester) async {
    await pumpShell(tester);
    detailIs(_detail(stage: 'sf'));
    final controller = build();

    await controller.refreshDetail();
    await tester.pumpAndSettle();

    expect(controller.myMatchReady.value, isFalse);
    verifyNever(() => online.fetchGame(any()));
  });

  testWidgets('a finished tournament opens nothing', (tester) async {
    await pumpShell(tester);
    detailIs(
      _detail(
        stage: 'f',
        gameId: 'game-final',
        matchStatus: 'finished',
        tournamentStatus: 'finished',
      ),
    );
    final controller = build();

    await controller.refreshDetail();
    await tester.pumpAndSettle();

    expect(controller.myMatchReady.value, isFalse);
    verifyNever(() => online.fetchGame(any()));
  });
}
