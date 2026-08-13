import 'dart:async';

import 'package:checkers/core/config/supabase_config.dart';
import 'package:checkers/engine/checkers_engine.dart';
import 'package:checkers/main.dart' as app;
import 'package:checkers/modules/game_board/controller/game_board_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

/// E2E: draw by agreement — the app offers a draw via the UI button and a
/// headless opponent accepts; the overlay shows the agreed draw.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('draw offer through the UI is accepted by the opponent', (
    tester,
  ) async {
    final b = SupabaseClient(SupabaseConfig.url, SupabaseConfig.anonKey);
    final bAuth = await b.auth.signInAnonymously();
    final bUid = bAuth.user!.id;
    await b.from('profiles').upsert({
      'id': bUid,
      'nickname': 'DrawB${DateTime.now().millisecondsSinceEpoch % 10000}',
      'is_anonymous': true,
    });
    final bJoin = await b.rpc<dynamic>(
      'join_online_game',
      params: {'p_preset': 'brazilian'},
    ) as Map;
    final gameId = bJoin['game_id'] as String;

    // Headless B: accept a draw offer as soon as it appears.
    var accepted = false;
    final done = Completer<void>();
    unawaited(() async {
      while (!done.isCompleted) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        try {
          final row =
              await b.from('games').select().eq('id', gameId).single();
          if (row['status'] == 'finished') {
            if (!done.isCompleted) {
              done.complete();
            }
            return;
          }
          final players =
              await b.from('game_players').select().eq('game_id', gameId);
          final mine = players.firstWhere((p) => p['uid'] == bUid);
          final offer = row['draw_offer_color'] as String?;
          if (offer != null && offer != mine['color']) {
            await b.rpc<dynamic>('respond_draw', params: {
              'p_game_id': gameId,
              'p_accept': true,
            });
            accepted = true;
          }
        } catch (_) {}
      }
    }());

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
          'D${DateTime.now().millisecondsSinceEpoch % 100000}',
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
    await tester.tap(find.byKey(const Key('play-people-brazilian')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('play-people-join')));

    await _settleUntil(
      tester,
      () => find.byKey(const Key('game-draw-button')).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
    );

    // Offer the draw through the UI.
    await tester.tap(find.byKey(const Key('game-draw-button')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('draw-pending-label')), findsOneWidget);

    final controller = Get.find<GameBoardController>();
    await _settleUntil(
      tester,
      () => controller.result.value == GameResult.draw,
      timeout: const Duration(seconds: 20),
    );
    expect(accepted, isTrue);
    expect(controller.resultReason.value, ResultReason.agreement);
    expect(find.byKey(const Key('game-over-title')), findsOneWidget);
    expect(find.byKey(const Key('game-rematch')), findsOneWidget);

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
