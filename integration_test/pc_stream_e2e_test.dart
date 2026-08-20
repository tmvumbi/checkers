import 'package:checkers/core/config/supabase_config.dart';
import 'package:checkers/main.dart' as app;
import 'package:checkers/modules/game_board/controller/game_board_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

/// E2E: a signed-in PC game is streamed to the backend (vs_pc, moves,
/// allow_undo flag) and a headless watcher shows up live in the avatars bar.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PC game streams to backend; watcher appears live', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final guestButton = find.byKey(const Key('landing-guest-button'));
    if (guestButton.evaluate().isNotEmpty) {
      await tester.tap(guestButton);
      await _settleUntil(
        tester,
        () =>
            find.byKey(const Key('edit-profile-nickname')).evaluate().isNotEmpty ||
            find.byKey(const Key('home-tab-play')).evaluate().isNotEmpty,
      );
      final nick = find.byKey(const Key('edit-profile-nickname'));
      if (nick.evaluate().isNotEmpty) {
        await tester.enterText(
          nick,
          'St${DateTime.now().millisecondsSinceEpoch % 100000}',
        );
        await tester.tap(find.byKey(const Key('edit-profile-save')));
      }
    }
    await _settleUntil(
      tester,
      () => find.byKey(const Key('home-play-pc-button')).evaluate().isNotEmpty,
    );

    // Start an Easy American PC game with undo enabled.
    await tester.tap(find.byKey(const Key('home-play-pc-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('play-pc-level-easy')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('play-pc-preset-american')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('play-pc-allow-undo')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('play-pc-allow-undo')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('play-pc-start')));
    await tester.tap(find.byKey(const Key('play-pc-start')));
    await _settleUntil(
      tester,
      () => find.byKey(const Key('game-turn-label')).evaluate().isNotEmpty,
    );

    final controller = Get.find<GameBoardController>();
    await _settleUntil(
      tester,
      () => controller.watchableGameId != null,
      timeout: const Duration(seconds: 15),
    );
    final gameId = controller.watchableGameId!;

    // Backend row carries the PC-game flags.
    final own = Supabase.instance.client;
    final row = await own.from('games').select().eq('id', gameId).single();
    expect(row['vs_pc'], isTrue);
    expect(row['allow_undo'], isTrue);
    expect(row['ai_level'], 'easy');
    expect(row['rated'], isFalse);

    // Human move + AI reply are mirrored to game_moves.
    final move = controller.legalMoves.first;
    controller.onSquareTapped(move.from);
    await tester.pump();
    controller.onSquareTapped(move.to);
    await _settleUntil(
      tester,
      () => controller.engine.moveHistory.length >= 2 && controller.isHumanTurn,
      timeout: const Duration(seconds: 30),
    );
    await _settleUntilAsync(
      tester,
      () async {
        final moves =
            await own.from('game_moves').select('ply').eq('game_id', gameId);
        return moves.length >= 2;
      },
      timeout: const Duration(seconds: 15),
    );

    // A headless watcher heartbeats; the avatars bar appears live.
    final watcher = SupabaseClient(SupabaseConfig.url, SupabaseConfig.anonKey);
    final watcherAuth = await watcher.auth.signInAnonymously();
    await watcher.from('profiles').upsert({
      'id': watcherAuth.user!.id,
      'nickname': 'Peek${DateTime.now().millisecondsSinceEpoch % 10000}',
      'is_anonymous': true,
    });
    await watcher.rpc<dynamic>(
      'watch_heartbeat',
      params: {'p_game_id': gameId},
    );

    await _settleUntil(
      tester,
      () => find.byKey(const Key('watchers-bar')).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 20),
    );

    // The watchers modal lists the spectator with a rating.
    await tester.tap(find.byKey(const Key('watchers-bar')));
    await _settleUntil(
      tester,
      () => find.textContaining('Peek').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 10),
    );
    await tester.tap(find.byKey(const Key('watchers-close')));
    await tester.pumpAndSettle();

    // Resign through the UI; the backend game finishes.
    await tester.tap(find.byKey(const Key('game-resign-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('game-resign-confirm')));
    await tester.pumpAndSettle();
    await _settleUntilAsync(
      tester,
      () async {
        final finalRow =
            await own.from('games').select('status').eq('id', gameId).single();
        return finalRow['status'] == 'finished';
      },
      timeout: const Duration(seconds: 15),
    );

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

Future<void> _settleUntilAsync(
  WidgetTester tester,
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 400));
    if (await condition()) {
      return;
    }
  }
  fail('Timed out waiting for async condition');
}
