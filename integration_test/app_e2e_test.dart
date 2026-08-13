import 'package:checkers/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// End-to-end smoke test against the real Supabase backend:
/// guest sign-in -> profile creation -> home tabs -> log out.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('guest can sign in, save a profile, browse tabs and log out', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Landing.
    final guestButton = find.byKey(const Key('landing-guest-button'));
    expect(guestButton, findsOneWidget);
    await tester.tap(guestButton);
    await _settleUntil(
      tester,
      () => find
          .byKey(const Key('edit-profile-nickname'))
          .evaluate()
          .isNotEmpty,
    );

    // Edit profile.
    final nickname = 'E2E${DateTime.now().millisecondsSinceEpoch % 100000}';
    await tester.enterText(
      find.byKey(const Key('edit-profile-nickname')),
      nickname,
    );
    await tester.tap(find.byKey(const Key('edit-profile-save')));
    await _settleUntil(
      tester,
      () => find.byKey(const Key('home-tab-play')).evaluate().isNotEmpty,
    );

    // Home: profile header shows the freshly saved nickname.
    await _settleUntil(
      tester,
      () => find.text(nickname).evaluate().isNotEmpty,
    );
    expect(find.byKey(const Key('home-play-pc-button')), findsOneWidget);

    // Tabs.
    await tester.tap(find.byKey(const Key('home-tab-watch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-tab-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('more-log-out-button')), findsOneWidget);

    // Log out (guest => confirmation modal).
    await tester.tap(find.byKey(const Key('more-log-out-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('more-log-out-confirm')));
    await _settleUntil(
      tester,
      () =>
          find.byKey(const Key('landing-guest-button')).evaluate().isNotEmpty,
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
