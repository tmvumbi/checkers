import 'package:checkers/shared/widgets/apple_sign_in_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'native Apple taps use the latest callback and respect busy state',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      MethodChannel? buttonChannel;
      final enabledUpdates = <bool>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          final args = call.arguments as Map;
          expect(args['viewType'], 'cd.dame/apple-sign-in-button');
          buttonChannel = MethodChannel(
            'cd.dame/apple-sign-in-button/${args['id']}',
          );
          messenger.setMockMethodCallHandler(buttonChannel!, (call) async {
            expect(call.method, 'setEnabled');
            enabledUpdates.add(call.arguments as bool);
            return null;
          });
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        if (buttonChannel != null) {
          messenger.setMockMethodCallHandler(buttonChannel!, null);
        }
      });

      Future<void> show(VoidCallback? onPressed) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppleSignInButton(
                onPressed: onPressed,
                fallbackLabel: 'Continue with Apple',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> nativeTap() async {
        await messenger.handlePlatformMessage(
          buttonChannel!.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onPressed'),
          ),
          (_) {},
        );
        await tester.pump();
      }

      var firstCalls = 0;
      var replacementCalls = 0;
      await show(() => firstCalls++);
      expect(find.byType(UiKitView), findsOneWidget);
      await nativeTap();
      expect(firstCalls, 1);

      await show(null);
      await nativeTap();
      expect(firstCalls, 1);

      await show(() => replacementCalls++);
      await nativeTap();
      expect(firstCalls, 1);
      expect(replacementCalls, 1);
      expect(enabledUpdates, [true, false, true]);

      await tester.pumpWidget(const SizedBox());
      await nativeTap();
      expect(replacementCalls, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
