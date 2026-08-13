import 'board_geometry.dart';
import 'move.dart';
import 'rules_config.dart';
import 'zobrist.dart';

enum PieceColor { white, black }

extension PieceColorX on PieceColor {
  PieceColor get opponent =>
      this == PieceColor.white ? PieceColor.black : PieceColor.white;
}

enum GameResult { ongoing, whiteWin, blackWin, draw }

enum ResultReason {
  none,
  noPieces,
  blocked,
  resignation,
  timeout,
  abandonment,
  agreement,
  repetition,
  kingMoves25,
  endgame16,
  endgame5,
  noProgress40,
}

class _UndoRecord {
  _UndoRecord({
    required this.move,
    required this.capturedKingsMask,
    required this.noProgressPlies,
    required this.endgameCountdown,
    required this.hash,
    required this.result,
    required this.resultReason,
  });

  final Move move;

  /// Which of the captured squares held kings (bit i == move.captured[i]).
  final int capturedKingsMask;
  final int noProgressPlies;
  final int endgameCountdown;
  final int hash;
  final GameResult result;
  final ResultReason resultReason;
}

/// Rules engine for draughts/checkers, parameterized by [RulesConfig]
/// (PRD §3). Pure Dart — shared by the UI, the AI isolate, and mirrored by
/// the TypeScript server engine.
class CheckersEngine {
  CheckersEngine({required this.config})
    : geometry = BoardGeometry.forSize(config.boardSize),
      zobrist = Zobrist.forSquareCount(config.squareCount) {
    reset();
  }

  final RulesConfig config;
  final BoardGeometry geometry;
  final Zobrist zobrist;

  int whiteBB = 0;
  int blackBB = 0;
  int kingsBB = 0;
  PieceColor sideToMove = PieceColor.white;

  /// Consecutive plies in which a king moved with no capture (25-move /
  /// 40-move rules; threshold depends on the rules family).
  int noProgressPlies = 0;

  /// Remaining plies before the armed FMJD endgame rule declares a draw;
  /// -1 when not armed.
  int endgameCountdown = -1;

  GameResult result = GameResult.ongoing;
  ResultReason resultReason = ResultReason.none;

  int hash = 0;
  final List<int> _hashHistory = [];
  final List<_UndoRecord> _undoStack = [];
  final List<Move> moveHistory = [];

  int get occupied => whiteBB | blackBB;

  void reset() {
    whiteBB = 0;
    blackBB = 0;
    kingsBB = 0;
    final men = config.menPerSide;
    for (var i = 0; i < men; i++) {
      blackBB |= 1 << i;
    }
    for (var i = config.squareCount - men; i < config.squareCount; i++) {
      whiteBB |= 1 << i;
    }
    sideToMove = PieceColor.white;
    noProgressPlies = 0;
    endgameCountdown = -1;
    result = GameResult.ongoing;
    resultReason = ResultReason.none;
    _undoStack.clear();
    moveHistory.clear();
    _hashHistory.clear();
    hash = _computeHash();
    _hashHistory.add(hash);
  }

  /// Loads an arbitrary position (tests, custom setups, replays).
  /// Squares are 0-based indices (FMJD number minus one).
  void loadPosition({
    required List<int> whiteSquares,
    required List<int> blackSquares,
    List<int> kingSquares = const [],
    PieceColor side = PieceColor.white,
  }) {
    whiteBB = 0;
    blackBB = 0;
    kingsBB = 0;
    for (final square in whiteSquares) {
      whiteBB |= 1 << square;
    }
    for (final square in blackSquares) {
      blackBB |= 1 << square;
    }
    for (final square in kingSquares) {
      kingsBB |= 1 << square;
    }
    sideToMove = side;
    noProgressPlies = 0;
    endgameCountdown = -1;
    result = GameResult.ongoing;
    resultReason = ResultReason.none;
    _undoStack.clear();
    moveHistory.clear();
    _hashHistory.clear();
    hash = _computeHash();
    _hashHistory.add(hash);
    _updateEndgameCountdown();
  }

  bool isWhiteAt(int square) => (whiteBB >> square) & 1 == 1;
  bool isBlackAt(int square) => (blackBB >> square) & 1 == 1;
  bool isKingAt(int square) => (kingsBB >> square) & 1 == 1;
  bool isEmptyAt(int square) => (occupied >> square) & 1 == 0;

  PieceColor? colorAt(int square) {
    if (isWhiteAt(square)) {
      return PieceColor.white;
    }
    if (isBlackAt(square)) {
      return PieceColor.black;
    }
    return null;
  }

  int _computeHash() {
    var h = 0;
    for (var square = 0; square < config.squareCount; square++) {
      final color = colorAt(square);
      if (color == null) {
        continue;
      }
      h ^= zobrist.pieceKeys[_pieceIndex(color, isKingAt(square))][square];
    }
    if (sideToMove == PieceColor.black) {
      h ^= zobrist.sideKey;
    }
    return h;
  }

  int _pieceIndex(PieceColor color, bool king) {
    return color == PieceColor.white
        ? (king ? Zobrist.whiteKing : Zobrist.whiteMan)
        : (king ? Zobrist.blackKing : Zobrist.blackMan);
  }

  // ---------------------------------------------------------------------
  // Move generation
  // ---------------------------------------------------------------------

  List<Move> legalMoves() => legalMovesFor(sideToMove);

  List<Move> legalMovesFor(PieceColor color) {
    if (result != GameResult.ongoing) {
      return const [];
    }
    final captures = _captureMoves(color);
    if (captures.isNotEmpty) {
      return captures;
    }
    return _quietMoves(color);
  }

  List<Move> _captureMoves(PieceColor color) {
    final own = color == PieceColor.white ? whiteBB : blackBB;
    final sequences = <Move>[];
    for (var square = 0; square < config.squareCount; square++) {
      if ((own >> square) & 1 == 0) {
        continue;
      }
      if (isKingAt(square)) {
        _kingCaptureDfs(color, square, square, 0, <int>[], sequences);
      } else {
        _manCaptureDfs(color, square, square, 0, <int>[], sequences);
      }
    }
    if (sequences.isEmpty) {
      return sequences;
    }

    var filtered = sequences;
    if (config.majorityCapture) {
      var max = 0;
      for (final move in filtered) {
        if (move.captured.length > max) {
          max = move.captured.length;
        }
      }
      final majority = max;
      filtered = [
        for (final move in filtered)
          if (move.captured.length == majority) move,
      ];
    }

    // Collapse sequences with identical legal identity (same origin,
    // destination and captured set — FMJD tie choices).
    final seen = <String>{};
    final deduped = <Move>[];
    for (final move in filtered) {
      if (seen.add(move.key)) {
        deduped.add(move);
      }
    }
    return deduped;
  }

  /// Directions a man of [color] may capture in.
  List<int> _manCaptureDirections(PieceColor color) {
    if (config.backwardCapture) {
      return BoardGeometry.allDirections;
    }
    return color == PieceColor.white
        ? const [BoardGeometry.northWest, BoardGeometry.northEast]
        : const [BoardGeometry.southWest, BoardGeometry.southEast];
  }

  void _manCaptureDfs(
    PieceColor color,
    int origin,
    int current,
    int capturedMask,
    List<int> path,
    List<Move> out,
  ) {
    final enemy = color == PieceColor.white ? blackBB : whiteBB;
    // The moving piece is off its origin square during the sequence;
    // captured pieces remain on the board as blockers (FMJD Art. 4.11).
    final blockers = (occupied & ~(1 << origin)) | capturedMask;
    var extended = false;

    for (final dir in _manCaptureDirections(color)) {
      final over = geometry.neighbors[dir][current];
      if (over == -1) {
        continue;
      }
      final overBit = 1 << over;
      if ((enemy & overBit) == 0 || (capturedMask & overBit) != 0) {
        continue;
      }
      final landing = geometry.neighbors[dir][over];
      if (landing == -1 || (blockers & (1 << landing)) != 0) {
        continue;
      }
      extended = true;
      path.add(landing);
      _manCaptureDfs(
        color,
        origin,
        landing,
        capturedMask | overBit,
        path,
        out,
      );
      path.removeLast();
    }

    if (!extended && capturedMask != 0) {
      final promotes = color == PieceColor.white
          ? geometry.isWhitePromotionSquare(current)
          : geometry.isBlackPromotionSquare(current);
      out.add(
        Move(
          from: origin,
          path: List.of(path),
          captured: _maskToList(capturedMask),
          promotes: promotes,
        ),
      );
    }
  }

  void _kingCaptureDfs(
    PieceColor color,
    int origin,
    int current,
    int capturedMask,
    List<int> path,
    List<Move> out,
  ) {
    final enemy = color == PieceColor.white ? blackBB : whiteBB;
    final blockers = (occupied & ~(1 << origin)) | capturedMask;
    var extended = false;

    for (final dir in BoardGeometry.allDirections) {
      var over = geometry.neighbors[dir][current];
      if (config.flyingKing) {
        // Slide over empties to the first piece.
        while (over != -1 && (blockers & (1 << over)) == 0) {
          over = geometry.neighbors[dir][over];
        }
      }
      if (over == -1) {
        continue;
      }
      final overBit = 1 << over;
      if ((enemy & overBit) == 0 || (capturedMask & overBit) != 0) {
        continue;
      }
      // Landing squares beyond the captured piece.
      var landing = geometry.neighbors[dir][over];
      while (landing != -1 && (blockers & (1 << landing)) == 0) {
        extended = true;
        path.add(landing);
        _kingCaptureDfs(
          color,
          origin,
          landing,
          capturedMask | overBit,
          path,
          out,
        );
        path.removeLast();
        if (!config.flyingKing) {
          break;
        }
        landing = geometry.neighbors[dir][landing];
      }
    }

    if (!extended && capturedMask != 0) {
      out.add(
        Move(
          from: origin,
          path: List.of(path),
          captured: _maskToList(capturedMask),
        ),
      );
    }
  }

  List<int> _maskToList(int mask) {
    final squares = <int>[];
    var remaining = mask;
    while (remaining != 0) {
      final square = _lowestBit(remaining);
      squares.add(square);
      remaining &= remaining - 1;
    }
    return squares;
  }

  int _lowestBit(int mask) {
    var index = 0;
    var m = mask;
    while ((m & 1) == 0) {
      m >>= 1;
      index++;
    }
    return index;
  }

  List<Move> _quietMoves(PieceColor color) {
    final own = color == PieceColor.white ? whiteBB : blackBB;
    final moves = <Move>[];
    final forward = color == PieceColor.white
        ? const [BoardGeometry.northWest, BoardGeometry.northEast]
        : const [BoardGeometry.southWest, BoardGeometry.southEast];

    for (var square = 0; square < config.squareCount; square++) {
      if ((own >> square) & 1 == 0) {
        continue;
      }
      if (isKingAt(square)) {
        for (final dir in BoardGeometry.allDirections) {
          var to = geometry.neighbors[dir][square];
          while (to != -1 && isEmptyAt(to)) {
            moves.add(Move(from: square, path: [to]));
            if (!config.flyingKing) {
              break;
            }
            to = geometry.neighbors[dir][to];
          }
        }
      } else {
        for (final dir in forward) {
          final to = geometry.neighbors[dir][square];
          if (to != -1 && isEmptyAt(to)) {
            final promotes = color == PieceColor.white
                ? geometry.isWhitePromotionSquare(to)
                : geometry.isBlackPromotionSquare(to);
            moves.add(Move(from: square, path: [to], promotes: promotes));
          }
        }
      }
    }
    return moves;
  }

  // ---------------------------------------------------------------------
  // Apply / undo
  // ---------------------------------------------------------------------

  void applyMove(Move move) {
    assert(result == GameResult.ongoing, 'game is over');
    final color = sideToMove;
    final mover = color == PieceColor.white ? whiteBB : blackBB;
    assert((mover >> move.from) & 1 == 1, 'no own piece on origin');

    final wasKing = isKingAt(move.from);
    var capturedKingsMask = 0;
    for (var i = 0; i < move.captured.length; i++) {
      if (isKingAt(move.captured[i])) {
        capturedKingsMask |= 1 << i;
      }
    }

    _undoStack.add(
      _UndoRecord(
        move: move,
        capturedKingsMask: capturedKingsMask,
        noProgressPlies: noProgressPlies,
        endgameCountdown: endgameCountdown,
        hash: hash,
        result: result,
        resultReason: resultReason,
      ),
    );
    moveHistory.add(move);

    final fromBit = 1 << move.from;
    final toBit = 1 << move.to;

    // Lift the moving piece.
    hash ^= zobrist.pieceKeys[_pieceIndex(color, wasKing)][move.from];
    if (color == PieceColor.white) {
      whiteBB &= ~fromBit;
    } else {
      blackBB &= ~fromBit;
    }
    kingsBB &= ~fromBit;

    // Remove captured pieces (all at once, at the end of the sequence).
    for (var i = 0; i < move.captured.length; i++) {
      final square = move.captured[i];
      final bit = 1 << square;
      final capturedKing = (capturedKingsMask >> i) & 1 == 1;
      hash ^=
          zobrist.pieceKeys[_pieceIndex(color.opponent, capturedKing)][square];
      whiteBB &= ~bit;
      blackBB &= ~bit;
      kingsBB &= ~bit;
    }

    // Land, possibly promoting.
    final becomesKing = wasKing || move.promotes;
    if (color == PieceColor.white) {
      whiteBB |= toBit;
    } else {
      blackBB |= toBit;
    }
    if (becomesKing) {
      kingsBB |= toBit;
    }
    hash ^= zobrist.pieceKeys[_pieceIndex(color, becomesKing)][move.to];

    sideToMove = color.opponent;
    hash ^= zobrist.sideKey;

    // Counters.
    if (move.isCapture || !wasKing) {
      noProgressPlies = 0;
    } else {
      noProgressPlies++;
    }
    _hashHistory.add(hash);

    _updateEndgameCountdown();
    _evaluateResult();
  }

  void undoMove() {
    final record = _undoStack.removeLast();
    moveHistory.removeLast();
    _hashHistory.removeLast();
    final move = record.move;
    final color = sideToMove.opponent;

    final toBit = 1 << move.to;
    final landedAsKing = isKingAt(move.to);
    final wasKing = landedAsKing && !move.promotes;

    // Lift the piece back off its landing square.
    if (color == PieceColor.white) {
      whiteBB &= ~toBit;
    } else {
      blackBB &= ~toBit;
    }
    kingsBB &= ~toBit;

    // Restore captured pieces.
    for (var i = 0; i < move.captured.length; i++) {
      final square = move.captured[i];
      final bit = 1 << square;
      if (color == PieceColor.white) {
        blackBB |= bit;
      } else {
        whiteBB |= bit;
      }
      if ((record.capturedKingsMask >> i) & 1 == 1) {
        kingsBB |= bit;
      }
    }

    // Put the mover back.
    final fromBit = 1 << move.from;
    if (color == PieceColor.white) {
      whiteBB |= fromBit;
    } else {
      blackBB |= fromBit;
    }
    if (wasKing) {
      kingsBB |= fromBit;
    }

    sideToMove = color;
    noProgressPlies = record.noProgressPlies;
    endgameCountdown = record.endgameCountdown;
    hash = record.hash;
    result = record.result;
    resultReason = record.resultReason;
  }

  // ---------------------------------------------------------------------
  // Result evaluation
  // ---------------------------------------------------------------------

  void _evaluateResult() {
    final mover = sideToMove;
    final own = mover == PieceColor.white ? whiteBB : blackBB;
    if (own == 0) {
      result = mover == PieceColor.white
          ? GameResult.blackWin
          : GameResult.whiteWin;
      resultReason = ResultReason.noPieces;
      return;
    }
    if (legalMovesFor(mover).isEmpty) {
      result = mover == PieceColor.white
          ? GameResult.blackWin
          : GameResult.whiteWin;
      resultReason = ResultReason.blocked;
      return;
    }

    // Threefold repetition (same position, same side to move).
    var repetitions = 0;
    for (final h in _hashHistory) {
      if (h == hash) {
        repetitions++;
      }
    }
    if (repetitions >= 3) {
      result = GameResult.draw;
      resultReason = ResultReason.repetition;
      return;
    }

    if (config.usesFmjdDrawRules) {
      if (noProgressPlies >= 50) {
        result = GameResult.draw;
        resultReason = ResultReason.kingMoves25;
        return;
      }
      if (endgameCountdown == 0) {
        result = GameResult.draw;
        resultReason = _endgameIsFiveMoveClass()
            ? ResultReason.endgame5
            : ResultReason.endgame16;
        return;
      }
    } else {
      if (noProgressPlies >= 80) {
        result = GameResult.draw;
        resultReason = ResultReason.noProgress40;
        return;
      }
    }
  }

  void _updateEndgameCountdown() {
    if (!config.usesFmjdDrawRules) {
      return;
    }
    final whiteMen = _popCount(whiteBB & ~kingsBB);
    final whiteKings = _popCount(whiteBB & kingsBB);
    final blackMen = _popCount(blackBB & ~kingsBB);
    final blackKings = _popCount(blackBB & kingsBB);

    final fiveClass = _isFiveMoveClass(
      whiteMen,
      whiteKings,
      blackMen,
      blackKings,
    );
    final sixteenClass = _isSixteenMoveClass(
      whiteMen,
      whiteKings,
      blackMen,
      blackKings,
    );

    if (fiveClass) {
      final limit = 10; // 5 moves each, in plies.
      if (endgameCountdown < 0 || endgameCountdown > limit) {
        endgameCountdown = limit;
      } else {
        endgameCountdown--;
      }
    } else if (sixteenClass) {
      final limit = 32; // 16 moves each, in plies.
      if (endgameCountdown < 0) {
        endgameCountdown = limit;
      } else {
        // Captures do NOT reset the 16-move count (FMJD Art. 6.3).
        endgameCountdown--;
      }
    } else {
      endgameCountdown = -1;
    }
  }

  bool _endgameIsFiveMoveClass() {
    final whiteMen = _popCount(whiteBB & ~kingsBB);
    final whiteKings = _popCount(whiteBB & kingsBB);
    final blackMen = _popCount(blackBB & ~kingsBB);
    final blackKings = _popCount(blackBB & kingsBB);
    return _isFiveMoveClass(whiteMen, whiteKings, blackMen, blackKings);
  }

  bool _isLoneKing(int men, int kings) => men == 0 && kings == 1;

  bool _isFiveMoveClass(
    int whiteMen,
    int whiteKings,
    int blackMen,
    int blackKings,
  ) {
    bool strongSide(int men, int kings) =>
        kings >= 1 && men + kings <= 2 && men + kings >= 1;
    return (_isLoneKing(blackMen, blackKings) &&
            strongSide(whiteMen, whiteKings)) ||
        (_isLoneKing(whiteMen, whiteKings) && strongSide(blackMen, blackKings));
  }

  bool _isSixteenMoveClass(
    int whiteMen,
    int whiteKings,
    int blackMen,
    int blackKings,
  ) {
    bool strongSide(int men, int kings) => kings >= 1 && men + kings == 3;
    return (_isLoneKing(blackMen, blackKings) &&
            strongSide(whiteMen, whiteKings)) ||
        (_isLoneKing(whiteMen, whiteKings) && strongSide(blackMen, blackKings));
  }

  int _popCount(int mask) {
    var count = 0;
    var m = mask;
    while (m != 0) {
      m &= m - 1;
      count++;
    }
    return count;
  }

  // ---------------------------------------------------------------------
  // External results (online play, PC resign)
  // ---------------------------------------------------------------------

  void declareResult(GameResult newResult, ResultReason reason) {
    result = newResult;
    resultReason = reason;
  }

  // ---------------------------------------------------------------------
  // Serialization: config + move list; state is derived by replay.
  // ---------------------------------------------------------------------

  Map<String, dynamic> toJson() {
    return {
      'config': config.toJson(),
      'moves': [for (final move in moveHistory) move.toJson()],
      'result': result.name,
      'result_reason': resultReason.name,
    };
  }

  factory CheckersEngine.fromJson(Map<String, dynamic> json) {
    final engine = CheckersEngine(
      config: RulesConfig.fromJson(json['config'] as Map<String, dynamic>),
    );
    for (final moveJson in json['moves'] as List) {
      engine.applyMove(Move.fromJson(moveJson as Map<String, dynamic>));
    }
    final storedResult = GameResult.values.byName(json['result'] as String);
    final storedReason = ResultReason.values.byName(
      json['result_reason'] as String,
    );
    if (storedResult != engine.result) {
      engine.declareResult(storedResult, storedReason);
    }
    return engine;
  }

  /// Counts leaf nodes of the legal-move tree — the standard move-generator
  /// correctness check.
  int perft(int depth) {
    if (depth == 0 || result != GameResult.ongoing) {
      return depth == 0 ? 1 : 0;
    }
    if (depth == 1) {
      return legalMoves().length;
    }
    var nodes = 0;
    for (final move in legalMoves()) {
      applyMove(move);
      nodes += perft(depth - 1);
      undoMove();
    }
    return nodes;
  }
}
