/// Difficulty profiles for the computer opponent (PRD §5.1.1).
///
/// Levels combine a think budget with deliberate imperfection: bounded
/// blunders and randomized picks among the top moves, so Easy feels human
/// rather than "perfect but shallow".
enum AiLevel { easy, medium, hard }

/// Feature switches for the search, used by the match harness to A/B
/// individual techniques. Shipping defaults are all-on.
class SearchOptions {
  const SearchOptions({
    this.usePvs = true,
    this.useAspiration = true,
    this.useLmr = true,
    this.useCounterMoves = true,
    this.useEarlyStop = true,
    this.evalVersion = 2,
  });

  /// Principal-variation search: null-window scout searches after the
  /// first move at every node.
  final bool usePvs;

  /// Narrow aspiration window around the previous iteration's score at
  /// the root (hard profile only).
  final bool useAspiration;

  /// Late-move reductions for quiet late moves in non-capture positions.
  final bool useLmr;

  /// Countermove heuristic in move ordering.
  final bool useCounterMoves;

  /// Stop early when the root best move has been stable for several
  /// iterations and most of the budget is spent.
  final bool useEarlyStop;

  /// 1 = legacy 4-term evaluation, 2 = tapered positional evaluation.
  final int evalVersion;

  static const SearchOptions all = SearchOptions();
  static const SearchOptions legacy = SearchOptions(
    usePvs: false,
    useAspiration: false,
    useLmr: false,
    useCounterMoves: false,
    useEarlyStop: false,
    evalVersion: 1,
  );
}

class AiConfig {
  const AiConfig({
    required this.level,
    required this.maxDepth,
    required this.budgetMs,
    required this.topN,
    required this.pickSecondBestChance,
    required this.blunderChance,
    required this.noiseCentiMen,
    this.search = SearchOptions.all,
    this.varietySeed = 0,
  });

  final AiLevel level;
  final int maxDepth;
  final int budgetMs;

  /// Number of top root moves eligible for randomized selection.
  final int topN;

  /// Chance of picking a non-best move among the eligible top moves.
  final double pickSecondBestChance;

  /// Chance of deliberately playing a move up to ~1 man worse than best.
  final double blunderChance;

  /// Deterministic evaluation noise amplitude (1 man = 100).
  final int noiseCentiMen;

  final SearchOptions search;

  /// Non-zero: in the opening, pick randomly (seeded) among near-equal
  /// best moves so consecutive games differ. Zero keeps the search fully
  /// deterministic per position.
  final int varietySeed;

  AiConfig withVarietySeed(int seed) => AiConfig(
    level: level,
    maxDepth: maxDepth,
    budgetMs: budgetMs,
    topN: topN,
    pickSecondBestChance: pickSecondBestChance,
    blunderChance: blunderChance,
    noiseCentiMen: noiseCentiMen,
    search: search,
    varietySeed: seed,
  );

  // Ladder rebalanced after playtesting (2026-08-14), and again 2026-08-21
  // when the hard profile was rebuilt (faster search, PVS/LMR, tapered
  // positional evaluation, 10s budget).
  static const AiConfig easy = AiConfig(
    level: AiLevel.easy,
    maxDepth: 8,
    budgetMs: 900,
    topN: 2,
    pickSecondBestChance: 0.2,
    blunderChance: 0.04,
    noiseCentiMen: 15,
  );

  static const AiConfig medium = AiConfig(
    level: AiLevel.medium,
    maxDepth: 24,
    budgetMs: 2800,
    topN: 1,
    pickSecondBestChance: 0,
    blunderChance: 0,
    noiseCentiMen: 0,
  );

  static const AiConfig hard = AiConfig(
    level: AiLevel.hard,
    maxDepth: 64,
    budgetMs: 10000,
    topN: 1,
    pickSecondBestChance: 0,
    blunderChance: 0,
    noiseCentiMen: 0,
  );

  static AiConfig forLevel(AiLevel level) {
    return switch (level) {
      AiLevel.easy => easy,
      AiLevel.medium => medium,
      AiLevel.hard => hard,
    };
  }
}
