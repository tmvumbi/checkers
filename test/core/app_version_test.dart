import 'dart:io';

import 'package:checkers/core/constants/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('displayed app version matches pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull);
    expect(AppStrings.currentAppVersion, match!.group(1));
  });
}
