import 'package:checkers/data/models/block_status.dart';
import 'package:checkers/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _TestBinding extends Bindings {
  @override
  void dependencies() {}
}

Future<void> _pumpBlocked(WidgetTester tester, BlockStatus status) async {
  await tester.pumpWidget(
    // How to Play needs no services, so it is a safe neutral start.
    CheckersApp(initialBinding: _TestBinding(), initialRoute: '/how-to-play'),
  );
  await tester.pumpAndSettle();
  Get.offAllNamed<void>('/blocked', arguments: status);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(Get.reset);

  testWidgets('permanent full block shows the permanent message', (
    tester,
  ) async {
    await _pumpBlocked(
      tester,
      const BlockStatus(level: BlockLevel.full, permanent: true),
    );
    expect(find.byKey(const Key('blocked-message')), findsOneWidget);
    expect(find.textContaining('permanently'), findsOneWidget);
  });

  testWidgets('timed full block shows the expiry date', (tester) async {
    await _pumpBlocked(
      tester,
      BlockStatus(
        level: BlockLevel.full,
        expiresAt: DateTime(2026, 8, 27, 14, 30),
      ),
    );
    expect(find.textContaining('2026-08-27 14:30'), findsOneWidget);
  });
}
