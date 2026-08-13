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

/// E2E online game: the app UI is player A; a headless Supabase client in
/// this test process is player B. Both hit the live backend.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('two players match and play online; A wins when B resigns', (
    tester,
  ) async {
    // ---- Player B: headless client joins matchmaking first.
    final b = SupabaseClient(SupabaseConfig.url, SupabaseConfig.anonKey);
    final bAuth = await b.auth.signInAnonymously();
    final bUid = bAuth.user!.id;
    await b.from('profiles').upsert({
      'id': bUid,
      'nickname': 'BotB${DateTime.now().millisecondsSinceEpoch % 10000}',
      'is_anonymous': true,
    });
    final bJoin = await b.rpc<dynamic>(
      'join_online_game',
      params: {'p_preset': 'american'},
    ) as Map;
    final gameId = bJoin['game_id'] as String;

    // Player B's turn loop runs concurrently with the UI flow below.
    var bResigned = false;
    final bDone = Completer<void>();
    Future<void> playerBLoop() async {
      final engine = CheckersEngine(config: RulesConfig.american);
      var resignAfterOwnMoves = 2;
      while (!bDone.isCompleted) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        try {
          final row = await b
              .from('games')
              .select()
              .eq('id', gameId)
              .single();
          if (row['status'] == 'finished' || row['status'] == 'abandoned') {
            bDone.complete();
            return;
          }
          if (row['status'] != 'playing') {
            // Keep the lobby seat alive against matchmaking GC.
            await b.rpc<dynamic>('touch_game_connection', params: {
              'p_game_id': gameId,
              'p_connected': true,
            });
            continue;
          }
          final players = await b
              .from('game_players')
              .select()
              .eq('game_id', gameId);
          final mine = players.firstWhere((p) => p['uid'] == bUid);
          final myColor = mine['color'] as String?;
          final state = (row['state'] as Map).cast<String, dynamic>();
          if (state['side'] != myColor) {
            continue;
          }
          // Rebuild local engine to current ply and pick the first move.
          final moveRows = await b
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
          if (resignAfterOwnMoves == 0) {
            await b.rpc<dynamic>(
              'resign_game',
              params: {'p_game_id': gameId},
            );
            bResigned = true;
            continue;
          }
          final move = engine.legalMoves().first;
          await b.rpc<dynamic>('submit_move', params: {
            'p_game_id': gameId,
            'p_move': move.toJson(),
            'p_expected_ply': engine.moveHistory.length,
          });
          resignAfterOwnMoves--;
        } catch (_) {
          // Transient errors (stale ply etc.) are retried next tick.
        }
      }
    }

    final bLoop = playerBLoop();

    // ---- Player A: the actual app UI.
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
          'A${DateTime.now().millisecondsSinceEpoch % 100000}',
        );
        await tester.tap(find.byKey(const Key('edit-profile-save')));
      }
    }
    await _settleUntil(
      tester,
      () =>
          find.byKey(const Key('home-play-people-button')).evaluate().isNotEmpty,
    );

    await tester.tap(find.byKey(const Key('home-play-people-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('play-people-american')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('play-people-join')));

    // Lobby → matched → board.
    await _settleUntil(
      tester,
      () => find.byKey(const Key('game-turn-label')).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
    );
    expect(find.byKey(const Key('clock-own-bank')), findsOneWidget);

    final controller = Get.find<GameBoardController>();

    // Play until B resigns: whenever it's A's turn, play the first move.
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline) &&
        controller.result.value == GameResult.ongoing) {
      await tester.pump(const Duration(milliseconds: 300));
      if (controller.isHumanTurn) {
        final move = controller.legalMoves.first;
        controller.onSquareTapped(move.from);
        await tester.pump();
        controller.onSquareTapped(move.to);
        await tester.pump(const Duration(milliseconds: 800));
      }
    }

    expect(bResigned, isTrue, reason: 'player B should have resigned');
    await _settleUntil(
      tester,
      () => find.byKey(const Key('game-over-title')).evaluate().isNotEmpty,
    );
    expect(controller.humanWon, isTrue);
    expect(controller.resultReason.value, ResultReason.resignation);

    if (!bDone.isCompleted) {
      bDone.complete();
    }
    await bLoop.timeout(const Duration(seconds: 5), onTimeout: () {});

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
