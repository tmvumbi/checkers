/// Difficulty profiles for the computer opponent (PRD §5.1.1).
///
/// Levels combine a think budget with deliberate imperfection: bounded
/// blunders and randomized picks among the top moves, so Easy feels human
/// rather than "perfect but shallow".
enum AiLevel { easy, medium, hard }

class AiConfig {
  const AiConfig({
    required this.level,
    required this.maxDepth,
    required this.budgetMs,
    required this.topN,
    required this.pickSecondBestChance,
    required this.blunderChance,
    required this.noiseCentiMen,
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

  // Ladder rebalanced after playtesting (2026-08-14): the original Medium
  // was too weak, so it became Easy, the original Hard became Medium, and
  // Hard is a new full-strength profile with a much larger budget on top of
  // the TT/killer move ordering in the search.
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
    maxDepth: 40,
    budgetMs: 6500,
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
