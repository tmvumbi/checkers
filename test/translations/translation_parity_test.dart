import 'package:checkers/translations/locales/en_us.dart';
import 'package:checkers/translations/locales/fr_fr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EN and FR locales cover exactly the same keys', () {
    final enKeys = enUs.keys.toSet();
    final frKeys = frFr.keys.toSet();
    expect(
      frKeys.difference(enKeys),
      isEmpty,
      reason: 'keys only in FR',
    );
    expect(
      enKeys.difference(frKeys),
      isEmpty,
      reason: 'keys missing in FR',
    );
  });

  test('no translation value is empty', () {
    for (final entry in enUs.entries) {
      expect(entry.value.trim(), isNotEmpty, reason: 'empty EN: ${entry.key}');
    }
    for (final entry in frFr.entries) {
      expect(entry.value.trim(), isNotEmpty, reason: 'empty FR: ${entry.key}');
    }
  });
}
