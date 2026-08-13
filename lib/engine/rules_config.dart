/// Rule parameterization for the checkers engine (PRD §3.1).
///
/// The two user-facing toggles plus board size map onto the named variants;
/// majority capture is carried as an independent parameter so it can become
/// a third toggle later without refactoring.
enum RulesPreset { international, brazilian, american, custom }

class RulesConfig {
  const RulesConfig({
    required this.boardSize,
    required this.backwardCapture,
    required this.flyingKing,
    required this.majorityCapture,
  }) : assert(boardSize == 8 || boardSize == 10, 'boardSize must be 8 or 10');

  final int boardSize;

  /// Men may capture backwards (FMJD Art. 4.1). Default ON.
  final bool backwardCapture;

  /// Kings slide any distance and land anywhere beyond a captured piece
  /// (FMJD Art. 3.9, 4.3). When OFF a king moves/captures one square at a
  /// time in any diagonal direction. Default ON.
  final bool flyingKing;

  /// The sequence capturing the most pieces is obligatory (FMJD Art. 4.13).
  final bool majorityCapture;

  static const RulesConfig international = RulesConfig(
    boardSize: 10,
    backwardCapture: true,
    flyingKing: true,
    majorityCapture: true,
  );

  static const RulesConfig brazilian = RulesConfig(
    boardSize: 8,
    backwardCapture: true,
    flyingKing: true,
    majorityCapture: true,
  );

  static const RulesConfig american = RulesConfig(
    boardSize: 8,
    backwardCapture: false,
    flyingKing: false,
    majorityCapture: false,
  );

  static RulesConfig fromPreset(RulesPreset preset) {
    return switch (preset) {
      RulesPreset.international => international,
      RulesPreset.brazilian => brazilian,
      RulesPreset.american || RulesPreset.custom => american,
    };
  }

  RulesPreset get preset {
    if (this == international) {
      return RulesPreset.international;
    }
    if (this == brazilian) {
      return RulesPreset.brazilian;
    }
    if (this == american) {
      return RulesPreset.american;
    }
    return RulesPreset.custom;
  }

  /// Number of playable (dark) squares.
  int get squareCount => boardSize * boardSize ~/ 2;

  /// Rows of playable squares per rank.
  int get squaresPerRow => boardSize ~/ 2;

  /// Men per side at the initial position.
  int get menPerSide => squaresPerRow * (boardSize ~/ 2 - 1);

  /// Draw family: FMJD counters for international-style rules, the 40-move
  /// rule for American-style rules (PRD §3.3).
  bool get usesFmjdDrawRules => majorityCapture;

  Map<String, dynamic> toJson() {
    return {
      'board_size': boardSize,
      'backward_capture': backwardCapture,
      'flying_king': flyingKing,
      'majority_capture': majorityCapture,
    };
  }

  factory RulesConfig.fromJson(Map<String, dynamic> json) {
    return RulesConfig(
      boardSize: (json['board_size'] as num).toInt(),
      backwardCapture: json['backward_capture'] as bool,
      flyingKing: json['flying_king'] as bool,
      majorityCapture: json['majority_capture'] as bool,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RulesConfig &&
        other.boardSize == boardSize &&
        other.backwardCapture == backwardCapture &&
        other.flyingKing == flyingKing &&
        other.majorityCapture == majorityCapture;
  }

  @override
  int get hashCode =>
      Object.hash(boardSize, backwardCapture, flyingKing, majorityCapture);
}
