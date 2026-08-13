import 'package:checkers/engine/checkers_engine.dart';
import 'package:checkers/engine/rules_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Perft anchors validate the move generator exhaustively.
///
/// International (10x10) reference values are the community-standard counts
/// for the FMJD initial position; American (8x8) values likewise (identical
/// for white-first play by symmetry).
void main() {
  group('perft — international 10x10', () {
    const expected = [9, 81, 658, 4265, 27117, 167140];

    test('depths 1..6 match reference values', () {
      final engine = CheckersEngine(config: RulesConfig.international);
      for (var depth = 1; depth <= expected.length; depth++) {
        expect(
          engine.perft(depth),
          expected[depth - 1],
          reason: 'perft($depth)',
        );
      }
    });
  });

  group('perft — american 8x8', () {
    const expected = [7, 49, 302, 1469, 7361, 36768];

    test('depths 1..6 match reference values', () {
      final engine = CheckersEngine(config: RulesConfig.american);
      for (var depth = 1; depth <= expected.length; depth++) {
        expect(
          engine.perft(depth),
          expected[depth - 1],
          reason: 'perft($depth)',
        );
      }
    });
  });

  group('perft — brazilian 8x8', () {
    test('shallow depths match american until captures diverge', () {
      final brazilian = CheckersEngine(config: RulesConfig.brazilian);
      expect(brazilian.perft(1), 7);
      expect(brazilian.perft(2), 49);
      expect(brazilian.perft(3), 302);
    });
  });
}
