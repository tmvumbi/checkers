import 'package:checkers/core/update_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = {
    'allowed_android_versions': ['1.0.0', '1.1.0'],
    'allowed_ios_versions': ['1.0.0'],
    'android_app_url': 'https://play.example/android',
    'ios_app_url': 'https://apps.example/ios',
  };

  group('UpdateGate.evaluate', () {
    test('active version passes on both platforms', () {
      expect(
        UpdateGate.evaluate(config, isIOS: false, currentVersion: '1.1.0')
            .updateRequired,
        isFalse,
      );
      expect(
        UpdateGate.evaluate(config, isIOS: true, currentVersion: '1.0.0')
            .updateRequired,
        isFalse,
      );
    });

    test('inactive version blocks with the platform store link', () {
      final android = UpdateGate.evaluate(
        config,
        isIOS: false,
        currentVersion: '0.9.0',
      );
      expect(android.updateRequired, isTrue);
      expect(android.storeUrl, 'https://play.example/android');

      final ios = UpdateGate.evaluate(
        config,
        isIOS: true,
        currentVersion: '1.1.0', // active on Android only
      );
      expect(ios.updateRequired, isTrue);
      expect(ios.storeUrl, 'https://apps.example/ios');
    });

    test('missing or empty lists fail open', () {
      expect(
        UpdateGate.evaluate(const {}, isIOS: false, currentVersion: '0.0.1')
            .updateRequired,
        isFalse,
      );
      expect(
        UpdateGate.evaluate(
          const {'allowed_ios_versions': <String>[]},
          isIOS: true,
          currentVersion: '0.0.1',
        ).updateRequired,
        isFalse,
      );
    });
  });
}
