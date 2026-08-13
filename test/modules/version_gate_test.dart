import 'package:checkers/modules/landing/controller/landing_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LandingController.compareVersions', () {
    test('orders dotted versions correctly', () {
      expect(LandingController.compareVersions('1.0.0', '1.0.0'), 0);
      expect(LandingController.compareVersions('1.0.0', '1.0.1'), isNegative);
      expect(LandingController.compareVersions('1.2.0', '1.0.9'), isPositive);
      expect(LandingController.compareVersions('2.0.0', '10.0.0'), isNegative);
      expect(LandingController.compareVersions('1.0', '1.0.0'), 0);
      expect(LandingController.compareVersions('bad', '1.0.0'), isNegative);
    });
  });
}
