// ignore_for_file: avoid_print
// Search benchmark: fixed positions at fixed depth. The speed-regression
// guard and determinism canary for AI work.
//
//   dart run tool/bench.dart [extraDepth]
//
// Prints nodes, time, NPS and the chosen move per position, plus totals.
// Best-move keys should stay stable across pure speedups; NPS is the
// number to watch.
import 'package:checkers/engine/ai/ai_config.dart';
import 'package:checkers/engine/ai/checkers_ai.dart';
import 'package:checkers/engine/checkers_engine.dart';
import 'package:checkers/engine/rules_config.dart';

class _BenchPosition {
  _BenchPosition(this.name, this.depth, this.build);

  final String name;
  final int depth;
  final CheckersEngine Function() build;
}

CheckersEngine _international() =>
    CheckersEngine(config: RulesConfig.international);

CheckersEngine _brazilian() =>
    CheckersEngine(config: RulesConfig.brazilian);

CheckersEngine _american() =>
    CheckersEngine(config: RulesConfig.american);

final List<_BenchPosition> _positions = [
  _BenchPosition('intl-opening', 9, _international),
  _BenchPosition('intl-midgame', 9, () {
    final engine = _international();
    engine.loadPosition(
      whiteSquares: [30, 31, 33, 35, 36, 38, 40, 41, 43, 45, 47, 48, 49, 46],
      blackSquares: [1, 2, 4, 6, 7, 9, 11, 12, 14, 16, 18, 19, 21, 23],
    );
    return engine;
  }),
  _BenchPosition('intl-kings-endgame', 13, () {
    final engine = _international();
    engine.loadPosition(
      whiteSquares: [45, 47, 22, 27],
      blackSquares: [2, 4, 13, 31],
      kingSquares: [22, 27, 13, 31],
    );
    return engine;
  }),
  _BenchPosition('intl-breakthrough', 11, () {
    final engine = _international();
    engine.loadPosition(
      whiteSquares: [7, 37, 41, 44, 46, 48],
      blackSquares: [15, 17, 19, 20, 22, 24],
    );
    return engine;
  }),
  _BenchPosition('brazilian-opening', 11, _brazilian),
  _BenchPosition('american-midgame', 11, () {
    final engine = _american();
    engine.loadPosition(
      whiteSquares: [17, 20, 22, 24, 25, 27, 29, 30],
      blackSquares: [2, 4, 5, 7, 9, 10, 12, 14],
    );
    return engine;
  }),
];

void main(List<String> args) {
  final extraDepth = args.isEmpty ? 0 : int.parse(args.first);
  var totalNodes = 0;
  var totalMs = 0;

  print(
    'position               depth      nodes      ms     kn/s  best (depth reached)',
  );
  for (final position in _positions) {
    final engine = position.build();
    final depth = position.depth + extraDepth;
    final config = AiConfig(
      level: AiLevel.hard,
      maxDepth: depth,
      budgetMs: 1 << 30,
      topN: 1,
      pickSecondBestChance: 0,
      blunderChance: 0,
      noiseCentiMen: 0,
    );
    final stopwatch = Stopwatch()..start();
    final choice = CheckersAi(engine, config).chooseMove();
    stopwatch.stop();
    final ms = stopwatch.elapsedMilliseconds;
    totalNodes += choice.nodes;
    totalMs += ms;
    final knps = ms == 0 ? 0 : choice.nodes ~/ ms;
    print(
      '${position.name.padRight(22)} ${'$depth'.padLeft(4)} '
      '${'${choice.nodes}'.padLeft(10)} ${'$ms'.padLeft(7)} '
      '${'$knps'.padLeft(8)}  ${choice.move.key} (d${choice.depth})',
    );
  }
  final totalKnps = totalMs == 0 ? 0 : totalNodes ~/ totalMs;
  print('${'TOTAL'.padRight(22)}      ${'$totalNodes'.padLeft(10)} '
      '${'$totalMs'.padLeft(7)} ${'$totalKnps'.padLeft(8)}');
}
