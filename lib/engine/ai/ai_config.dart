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

  static const AiConfig easy = AiConfig(
    level: AiLevel.easy,
    maxDepth: 4,
    budgetMs: 300,
    topN: 4,
    pickSecondBestChance: 0.5,
    blunderChance: 0.15,
    noiseCentiMen: 40,
  );

  static const AiConfig medium = AiConfig(
    level: AiLevel.medium,
    maxDepth: 8,
    budgetMs: 900,
    topN: 2,
    pickSecondBestChance: 0.2,
    blunderChance: 0.04,
    noiseCentiMen: 15,
  );

  static const AiConfig hard = AiConfig(
    level: AiLevel.hard,
    maxDepth: 24,
    budgetMs: 2800,
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
