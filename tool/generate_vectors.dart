// Generates the shared engine test-vector suite consumed by the JS engine
// tests (supabase/engine/engine_test.ts). Run with:
//   dart run tool/generate_vectors.dart
//
// Vectors cover all three presets: scripted pseudo-random games recording,
// at every ply, the position and the exact legal move set (by move key).
import 'dart:convert';
import 'dart:io';

import 'package:checkers/engine/checkers_engine.dart';
import 'package:checkers/engine/rules_config.dart';

void main() {
  final vectors = <Map<String, dynamic>>[];

  for (final entry in {
    'international': RulesConfig.international,
    'brazilian': RulesConfig.brazilian,
    'american': RulesConfig.american,
  }.entries) {
    // Three deterministic games per preset with different move-pick seeds.
    for (var seed = 1; seed <= 3; seed++) {
      final engine = CheckersEngine(config: entry.value);
      var ply = 0;
      while (engine.result == GameResult.ongoing && ply < 120) {
        final moves = engine.legalMoves();
        vectors.add({
          'preset': entry.key,
          'seed': seed,
          'ply': ply,
          'board': _boardArray(engine),
          'side': engine.sideToMove.name,
          'legal_move_keys': (moves.map((m) => m.key).toList()..sort()),
        });
        final pick = (ply * seed * 7919 + seed * 31) % moves.length;
        engine.applyMove(moves[pick]);
        ply++;
      }
      vectors.add({
        'preset': entry.key,
        'seed': seed,
        'ply': ply,
        'board': _boardArray(engine),
        'side': engine.sideToMove.name,
        'result': engine.result.name,
        'result_reason': engine.resultReason.name,
        'legal_move_keys': const <String>[],
      });
    }
  }

  final out = File('supabase/engine/test_vectors.json');
  out.writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
    'generator': 'tool/generate_vectors.dart',
    'vectors': vectors,
  }));
  stdout.writeln('wrote ${vectors.length} vectors to ${out.path}');
}

List<int> _boardArray(CheckersEngine engine) {
  // 0 empty, 1 white man, 2 white king, 3 black man, 4 black king —
  // must match the JS engine encoding.
  return [
    for (var s = 0; s < engine.config.squareCount; s++)
      engine.isWhiteAt(s)
          ? (engine.isKingAt(s) ? 2 : 1)
          : engine.isBlackAt(s)
          ? (engine.isKingAt(s) ? 4 : 3)
          : 0,
  ];
}
