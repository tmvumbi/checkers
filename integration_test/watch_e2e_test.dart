import 'dart:async';

import 'package:checkers/core/config/supabase_config.dart';
import 'package:checkers/engine/checkers_engine.dart';
import 'package:checkers/engine/move.dart';
import 'package:checkers/engine/rules_config.dart';
import 'package:checkers/main.dart' as app;
import 'package:checkers/modules/game_board/controller/game_board_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

/// E2E: two headless players play a public game; the app UI spectates it
/// live from the Watch tab and the Top 30 tab shows ranked players.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('spectator watches a live game; leaderboard renders', (
    tester,
  ) async {
    // Two headless players.
    Future<(SupabaseClient, String)> makePlayer(String prefix) async {
      final client = SupabaseClient(SupabaseConfig.url, SupabaseConfig.anonKey);
      final auth = await client.auth.signInAnonymously();
      final uid = auth.user!.id;
      await client.from('profiles').upsert({
        'id': uid,
        'nickname': '$prefix${DateTime.now().millisecondsSinceEpoch % 10000}',
        'is_anonymous': true,
      });
      return (client, uid);
    }

    final (clientA, uidA) = await makePlayer('WA');
    final (clientB, uidB) = await makePlayer('WB');
    final joinA = await clientA.rpc<dynamic>(
      'join_online_game',
      params: {'p_preset': 'brazilian'},
    ) as Map;
    final joinB = await clientB.rpc<dynamic>(
      'join_online_game',
      params: {'p_preset': 'brazilian'},
    ) as Map;
    expect(joinA['game_id'], joinB['game_id'],
        reason: 'headless players should match each other');
    final gameId = joinA['game_id'] as String;

    // Headless game loop: both players alternate slow moves, ~12 plies,
    // then A resigns so the spectator sees a result.
    final done = Completer<void>();
    unawaited(() async {
      final engine = CheckersEngine(config: RulesConfig.brazilian);
      var plies = 0;
      while (!done.isCompleted && plies < 60) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        try {
          final row = await clientA
              .from('games')
              .select()
              .eq('id', gameId)
              .single();
          if (row['status'] != 'playing') {
            continue;
          }
          final state = (row['state'] as Map).cast<String, dynamic>();
          final side = state['side'] as String;
          final players =
              await clientA.from('game_players').select().eq('game_id', gameId);
          final mover = players.firstWhere((p) => p['color'] == side);
          final moverClient = mover['uid'] == uidA ? clientA : clientB;

          final moveRows = await clientA
              .from('game_moves')
              .select('ply, move')
              .eq('game_id', gameId)
              .order('ply', ascending: true);
          engine.reset();
          for (final mr in moveRows) {
            engine.applyMove(
              Move.fromJson((mr['move'] as Map).cast<String, dynamic>()),
            );
          }
          plies = engine.moveHistory.length;
          if (plies >= 12) {
            await clientA.rpc<dynamic>(
              'resign_game',
              params: {'p_game_id': gameId},
            );
            if (!done.isCompleted) {
              done.complete();
            }
            return;
          }
          final move = engine.legalMoves().first;
          await moverClient.rpc<dynamic>('submit_move', params: {
            'p_game_id': gameId,
            'p_move': move.toJson(),
            'p_expected_ply': plies,
          });
        } catch (_) {}
      }
      if (!done.isCompleted) {
        done.complete();
      }
    }());

    // The app: guest signs in and opens the Watch tab.
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
          'S${DateTime.now().millisecondsSinceEpoch % 100000}',
        );
        await tester.tap(find.byKey(const Key('edit-profile-save')));
      }
    }
    await _settleUntil(
      tester,
      () => find.byKey(const Key('home-tab-watch')).evaluate().isNotEmpty,
    );

    await tester.tap(find.byKey(const Key('home-tab-watch')));
    await _settleUntil(
      tester,
      () => find.byKey(Key('watch-game-$gameId')).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
    );

    await tester.tap(find.byKey(Key('watch-game-$gameId')));
    await _settleUntil(
      tester,
      () => find.byKey(const Key('clock-own-bank')).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 20),
    );

    // Watch moves stream in live.
    final controller = Get.find<GameBoardController>();
    expect(controller.isWatching, isTrue);
    final seenPlies = controller.engine.moveHistory.length;
    await _settleUntil(
      tester,
      () => controller.engine.moveHistory.length > seenPlies,
      timeout: const Duration(seconds: 30),
    );

    // Wait for the resignation result.
    await _settleUntil(
      tester,
      () => controller.result.value != GameResult.ongoing,
      timeout: const Duration(seconds: 60),
    );
    expect(find.byKey(const Key('game-over-title')), findsOneWidget);
    // Spectators get no rematch button.
    expect(find.byKey(const Key('game-rematch')), findsNothing);

    await tester.tap(find.byKey(const Key('game-back-home')));
    await _settleUntil(
      tester,
      () => find.byKey(const Key('home-tab-leaderboard')).evaluate().isNotEmpty,
    );

    // Top 30 renders ranked players (earlier games produced rated players).
    await tester.tap(find.byKey(const Key('home-tab-leaderboard')));
    await _settleUntil(
      tester,
      () => find.byKey(const Key('leaderboard-row-0')).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 15),
    );

    if (!done.isCompleted) {
      done.complete();
    }
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
