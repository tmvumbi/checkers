/// Diagonal geometry over the playable (dark) squares.
///
/// Squares use FMJD numbering internally as 0-based indices 0..N-1
/// (FMJD square 1 == index 0), numbered row by row from the top from
/// White's point of view. Black's men start on the low indices and move
/// "down" (increasing row); White moves "up" (decreasing row) and promotes
/// on row 0.
class BoardGeometry {
  BoardGeometry._(this.boardSize)
    : squareCount = boardSize * boardSize ~/ 2,
      squaresPerRow = boardSize ~/ 2 {
    _buildNeighborTables();
  }

  static final Map<int, BoardGeometry> _cache = {};

  factory BoardGeometry.forSize(int boardSize) {
    return _cache.putIfAbsent(boardSize, () => BoardGeometry._(boardSize));
  }

  final int boardSize;
  final int squareCount;
  final int squaresPerRow;

  /// Direction indices.
  static const int northWest = 0;
  static const int northEast = 1;
  static const int southWest = 2;
  static const int southEast = 3;
  static const List<int> allDirections = [0, 1, 2, 3];

  /// neighbors[dir][square] -> adjacent playable square index or -1.
  late final List<List<int>> neighbors;

  int rowOf(int square) => square ~/ squaresPerRow;

  /// 0-based column on the full board (0..boardSize-1).
  int colOf(int square) {
    final row = rowOf(square);
    final posInRow = square % squaresPerRow;
    return row.isEven ? posInRow * 2 + 1 : posInRow * 2;
  }

  int? indexOf(int row, int col) {
    if (row < 0 || row >= boardSize || col < 0 || col >= boardSize) {
      return null;
    }
    // Dark squares sit on (row+col) odd in this orientation.
    if ((row + col).isEven) {
      return null;
    }
    return row * squaresPerRow + col ~/ 2;
  }

  void _buildNeighborTables() {
    neighbors = List.generate(4, (_) => List.filled(squareCount, -1));
    for (var square = 0; square < squareCount; square++) {
      final row = rowOf(square);
      final col = colOf(square);
      neighbors[northWest][square] = _safe(row - 1, col - 1);
      neighbors[northEast][square] = _safe(row - 1, col + 1);
      neighbors[southWest][square] = _safe(row + 1, col - 1);
      neighbors[southEast][square] = _safe(row + 1, col + 1);
    }
  }

  int _safe(int row, int col) => indexOf(row, col) ?? -1;

  /// Promotion row for white pieces is row 0; for black the last row.
  bool isWhitePromotionSquare(int square) => rowOf(square) == 0;

  bool isBlackPromotionSquare(int square) => rowOf(square) == boardSize - 1;
}
