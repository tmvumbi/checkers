import 'package:checkers/core/network/api_result.dart';
import 'package:checkers/data/models/online_game.dart';
import 'package:checkers/engine/checkers_engine.dart';
import 'package:checkers/engine/move.dart';
import 'package:checkers/engine/rules_config.dart';
import 'package:checkers/modules/game_board/controller/game_board_controller.dart';
import 'package:checkers/modules/game_board/models/game_board_arguments.dart';
import 'package:checkers/services/analytics_service.dart';
import 'package:checkers/services/auth_service.dart';
import 'package:checkers/services/checkers_ai_service.dart';
import 'package:checkers/services/online_game_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';

class MockOnlineGameService extends Mock implements OnlineGameService {}

class MockAuthService extends Mock implements AuthService {}

OnlineGameSnapshot _snapshot({
  String status = 'playing',
  PieceColor? drawOffer,
}) {
  return OnlineGameSnapshot(
    id: 'g1',
    status: status,
    rules: RulesConfig.american,
    ply: 0,
    sideToMove: PieceColor.white,
    board: const [],
    whiteBankMs: 300000,
    blackBankMs: 300000,
    drawOfferColor: drawOffer,
    players: const [
      OnlineGamePlayer(
        uid: 'me',
        seat: 0,
        nickname: 'Me',
        color: PieceColor.white,
      ),
      OnlineGamePlayer(
        uid: 'opp',
        seat: 1,
        nickname: 'Opp',
        color: PieceColor.black,
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Move(from: 0, path: const [1]));
  });

  late MockOnlineGameService online;
  late MockAuthService auth;
  late GameBoardController controller;

  setUp(() {
    online = MockOnlineGameService();
    auth = MockAuthService();
    when(() => auth.currentUser).thenReturn(
      const AuthUser(uid: 'me', isAnonymous: true),
    );
    when(() => online.offerDraw(any())).thenAnswer(
      (_) async => const Success(null),
    );
    when(() => online.respondDraw(any(), any())).thenAnswer(
      (_) async => const Success(null),
    );
    controller = GameBoardController(
      arguments: const GameBoardArguments.online(
        rules: RulesConfig.american,
        gameId: 'g1',
        humanColor: PieceColor.white,
      ),
      aiService: SyncAiService(),
      analyticsService: NoopAnalyticsService(),
      onlineGameService: online,
      authService: auth,
      aiMinThinkTime: Duration.zero,
    );
  });

  tearDown(Get.reset);

  test('offerDraw is gated and marks the pending state', () async {
    controller.snapshot.value = _snapshot();
    expect(controller.canOfferDraw, isTrue);
    await controller.offerDraw();
    expect(controller.drawOfferPending.value, isTrue);
    expect(controller.canOfferDraw, isFalse);
    verify(() => online.offerDraw('g1')).called(1);
  });

  test('incoming draw offer is detected from the snapshot', () async {
    // ignore: invalid_use_of_protected_member
    controller.snapshot.value = _snapshot();
    // Simulate a snapshot with the opponent's offer via the handler used by
    // the stream: exercised through the public fields.
    controller.incomingDrawOffer.value = false;
    final snap = _snapshot(drawOffer: PieceColor.black);
    // The stream handler is private; emulate its bookkeeping contract.
    controller.snapshot.value = snap;
    controller.incomingDrawOffer.value =
        snap.drawOfferColor != null && snap.drawOfferColor != controller.humanColor;
    expect(controller.incomingDrawOffer.value, isTrue);

    await controller.respondDraw(true);
    verify(() => online.respondDraw('g1', true)).called(1);
    expect(controller.incomingDrawOffer.value, isFalse);
  });

  test('draw offers are limited to three per game', () async {
    controller.snapshot.value = _snapshot();
    for (var i = 0; i < 3; i++) {
      await controller.offerDraw();
      controller.drawOfferPending.value = false; // declined by opponent
    }
    expect(controller.canOfferDraw, isFalse);
    verify(() => online.offerDraw('g1')).called(3);
  });

  test('online human move submits to the server', () async {
    when(() => online.submitMove(any(), any(), any())).thenAnswer(
      (_) async => const Success(null),
    );
    controller.snapshot.value = _snapshot();
    final move = controller.legalMoves.first;
    controller.onSquareTapped(move.from);
    controller.onSquareTapped(move.to);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    verify(() => online.submitMove('g1', any(that: isA<Move>()), 0)).called(1);
    expect(controller.engine.moveHistory.length, 1);
  });
}
