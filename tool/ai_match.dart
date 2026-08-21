// ignore_for_file: avoid_print
// AI-vs-AI match harness: quantifies strength differences between search
// profiles before they ship.
//
//   dart run tool/ai_match.dart --games 100 --budget-ms 250 \
//       --a new --b legacy --variant international
//
// Games come in pairs: each seeded random opening (3 plies) is played with
// colors swapped, which cancels opening bias. Reports W/L/D, score and an
// Elo estimate with a 95% confidence interval.
import 'dart:math';

import 'package:checkers/engine/ai/ai_config.dart';
import 'package:checkers/engine/ai/checkers_ai.dart';
import 'package:checkers/engine/checkers_engine.dart';
import 'package:checkers/engine/move.dart';
import 'package:checkers/engine/rules_config.dart';

AiConfig _profile(String name, int budgetMs) {
  final search = switch (name) {
    'new' => SearchOptions.all,
    'legacy' => SearchOptions.legacy,
    'noeval' => const SearchOptions(evalVersion: 1),
    'nolmr' => const SearchOptions(useLmr: false),
    'nopvs' => const SearchOptions(usePvs: false, useAspiration: false),
    _ => throw ArgumentError('unknown profile: $name'),
  };
  return AiConfig(
    level: AiLevel.hard,
    maxDepth: 64,
    budgetMs: budgetMs,
    topN: 1,
    pickSecondBestChance: 0,
    blunderChance: 0,
    noiseCentiMen: 0,
    search: search,
  );
}

RulesConfig _variant(String name) => switch (name) {
  'international' => RulesConfig.international,
  'brazilian' => RulesConfig.brazilian,
  'american' => RulesConfig.american,
  _ => throw ArgumentError('unknown variant: $name'),
};

/// 1 = white wins, 0 = black wins, 0.5 = draw (white's perspective).
double _playGame(
  RulesConfig rules,
  AiConfig whiteConfig,
  AiConfig blackConfig,
  int openingSeed,
) {
  final engine = CheckersEngine(config: rules);
  final random = Random(openingSeed);
  for (var i = 0; i < 3; i++) {
    final moves = engine.legalMoves();
    if (moves.isEmpty || engine.result != GameResult.ongoing) {
      break;
    }
    engine.applyMove(moves[random.nextInt(moves.length)]);
  }
  final whiteAi = CheckersAi(engine, whiteConfig);
  final blackAi = CheckersAi(engine, blackConfig);

  var plies = 0;
  while (engine.result == GameResult.ongoing && plies < 300) {
    final ai = engine.sideToMove == PieceColor.white ? whiteAi : blackAi;
    final Move move = ai.chooseMove().move;
    engine.applyMove(move);
    plies++;
  }
  return switch (engine.result) {
    GameResult.whiteWin => 1,
    GameResult.blackWin => 0,
    _ => 0.5,
  };
}

void main(List<String> args) {
  var games = 100;
  var budgetMs = 250;
  var profileA = 'new';
  var profileB = 'legacy';
  var variant = 'international';
  for (var i = 0; i < args.length - 1; i++) {
    switch (args[i]) {
      case '--games':
        games = int.parse(args[i + 1]);
      case '--budget-ms':
        budgetMs = int.parse(args[i + 1]);
      case '--a':
        profileA = args[i + 1];
      case '--b':
        profileB = args[i + 1];
      case '--variant':
        variant = args[i + 1];
    }
  }
  final rules = _variant(variant);
  final configA = _profile(profileA, budgetMs);
  final configB = _profile(profileB, budgetMs);

  var wins = 0, losses = 0, draws = 0;
  final pairs = games ~/ 2;
  final stopwatch = Stopwatch()..start();
  for (var pair = 0; pair < pairs; pair++) {
    // A as white, then A as black, same opening.
    final first = _playGame(rules, configA, configB, 1000 + pair);
    final second = 1 - _playGame(rules, configB, configA, 1000 + pair);
    for (final result in [first, second]) {
      if (result == 1) {
        wins++;
      } else if (result == 0) {
        losses++;
      } else {
        draws++;
      }
    }
    final played = (pair + 1) * 2;
    final score = (wins + draws / 2) / played;
    print(
      'after $played: +$wins -$losses =$draws  '
      'score ${(score * 100).toStringAsFixed(1)}%  '
      '(${stopwatch.elapsed.inSeconds}s)',
    );
  }

  final played = pairs * 2;
  final score = (wins + draws / 2) / played;
  final safeScore = score.clamp(0.001, 0.999);
  final elo = -400 * log(1 / safeScore - 1) / ln10;
  final stderr = sqrt(safeScore * (1 - safeScore) / played);
  final low = (safeScore - 1.96 * stderr).clamp(0.001, 0.999);
  final high = (safeScore + 1.96 * stderr).clamp(0.001, 0.999);
  final eloLow = -400 * log(1 / low - 1) / ln10;
  final eloHigh = -400 * log(1 / high - 1) / ln10;
  print('');
  print('$profileA vs $profileB @ ${budgetMs}ms, $variant');
  print('+$wins -$losses =$draws  score ${(score * 100).toStringAsFixed(1)}%');
  print(
    'Elo ${elo.toStringAsFixed(0)} '
    '[${eloLow.toStringAsFixed(0)}, ${eloHigh.toStringAsFixed(0)}] (95% CI)',
  );
}
