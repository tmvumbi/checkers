/// Deterministic Zobrist keys for position hashing (repetition detection and
/// the AI transposition table). Uses a fixed-seed xorshift64* generator so
/// Dart and the TypeScript port produce identical keys.
class Zobrist {
  Zobrist._(int squareCount) {
    var state = 0x9E3779B97F4A7C15;
    int next() {
      state ^= (state >>> 12);
      state ^= (state << 25) & 0xFFFFFFFFFFFFFFFF;
      state ^= (state >>> 27);
      return (state * 0x2545F4914F6CDD1D) & 0x7FFFFFFFFFFFFFFF;
    }

    pieceKeys = List.generate(
      4,
      (_) => List.generate(squareCount, (_) => next()),
    );
    sideKey = next();
  }

  static final Map<int, Zobrist> _cache = {};

  factory Zobrist.forSquareCount(int squareCount) {
    return _cache.putIfAbsent(squareCount, () => Zobrist._(squareCount));
  }

  /// Indexed by [whiteMan, whiteKing, blackMan, blackKing][square].
  late final List<List<int>> pieceKeys;
  late final int sideKey;

  static const int whiteMan = 0;
  static const int whiteKing = 1;
  static const int blackMan = 2;
  static const int blackKing = 3;
}
