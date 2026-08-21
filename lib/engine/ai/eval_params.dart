/// Every tunable weight of the v2 evaluation in one place (centi-men:
/// one man = 100). Hand-tuned initially; validated with tool/ai_match.dart.
abstract final class EvalParams {
  // Material.
  static const int man = 100;
  static const int flyingKingOpen = 280;
  static const int flyingKingEnd = 330;
  static const int simpleKingOpen = 135;
  static const int simpleKingEnd = 160;

  // Man piece-square terms (folded into the PSQTs at startup).
  static const int advanceOpen = 2; // per row toward promotion
  static const int advanceEnd = 5;
  static const int backRowOpen = 12; // guard the promotion row early
  static const int backRowEnd = 0;
  static const int edgeOpen = -8; // half the capture cover
  static const int edgeEnd = -3;
  static const int centerOpen = 7; // the strong central columns
  static const int centerEnd = 2;
  static const int nearPromotionOpen = 10; // rows 1-2 from promotion
  static const int nearPromotionEnd = 25;

  // Side to move.
  static const int tempo = 8;

  // Structure.
  static const int supportedMan = 4; // friendly piece on a rear diagonal
  static const int isolatedMan = -8; // no friendly neighbor at all

  // Wing balance, 10x10 only: men spread over both wings.
  static const int wingImbalance = -7; // per man beyond a 2-man skew

  // Runaway man: empty promotion cone.
  static const int runawayBase = 55;
  static const int runawayPerRow = 22; // closer rows are worth more

  // Kings.
  static const int kingMobilityOpen = 3; // per free step, capped
  static const int kingMobilityEnd = 4;
  static const int kingMobilityCap = 6;
  static const int trappedKing = -30; // mobility <= 1

  // Endgames: nudge the stronger side to trade pieces.
  static const int tradeWhenAhead = 2; // per missing piece when ahead
}
