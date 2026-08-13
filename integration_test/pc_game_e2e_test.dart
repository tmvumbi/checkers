import 'package:checkers/main.dart' as app;
import 'package:checkers/modules/game_board/controller/game_board_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

/// E2E: guest signs in and plays a PC game (easy, American 8x8) — makes a
/// move, gets an AI reply, resigns, sees the game-over overlay, returns home.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full PC game session', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Sign in as guest (or reuse an existing session if one survives).
    final guestButton = find.byKey(const Key('landing-guest-button'));
    if (guestButton.evaluate().isNotEmpty) {
      await tester.tap(guestButton);
      await _settleUntil(
        tester,
        () =>
            find.byKey(const Key('edit-profile-nickname')).evaluate().isNotEmpty ||
            find.byKey(const Key('home-tab-play')).evaluate().isNotEmpty,
      );
      final nicknameField = find.byKey(const Key('edit-profile-nickname'));
      if (nicknameField.evaluate().isNotEmpty) {
        await tester.enterText(
          nicknameField,
          'PC${DateTime.now().millisecondsSinceEpoch % 100000}',
        );
        await tester.tap(find.byKey(const Key('edit-profile-save')));
      }
    }
    await _settleUntil(
      tester,
      () => find.byKey(const Key('home-play-pc-button')).evaluate().isNotEmpty,
    );

    // Open the PC setup modal, pick Easy + American 8x8, start.
    await tester.tap(find.byKey(const Key('home-play-pc-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('play-pc-level-easy')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('play-pc-preset-american')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('play-pc-start')));
    await tester.tap(find.byKey(const Key('play-pc-start')));
    await _settleUntil(
      tester,
      () => find.byKey(const Key('game-turn-label')).evaluate().isNotEmpty,
    );

    // Play one human move through the controller API (tap targets on the
    // board depend on pixel geometry; the controller is the same code path
    // as onTapUp).
    final controller = Get.find<GameBoardController>();
    expect(controller.isHumanTurn, isTrue);
    final move = controller.legalMoves.first;
    controller.onSquareTapped(move.from);
    await tester.pump();
    controller.onSquareTapped(move.to);

    // Wait for the human animation + AI reply to land.
    await _settleUntil(
      tester,
      () =>
          controller.engine.moveHistory.length >= 2 &&
          controller.isHumanTurn,
      timeout: const Duration(seconds: 30),
    );
    expect(controller.engine.moveHistory.length, greaterThanOrEqualTo(2));

    // Resign via the UI and check the game-over overlay.
    await tester.tap(find.byKey(const Key('game-resign-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('game-resign-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('game-over-title')), findsOneWidget);

    // Back home.
    await tester.tap(find.byKey(const Key('game-back-home')));
    await _settleUntil(
      tester,
      () => find.byKey(const Key('home-play-pc-button')).evaluate().isNotEmpty,
    );
  });
}

Future<void> _settleUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (condition()) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Timed out waiting for condition');
}
