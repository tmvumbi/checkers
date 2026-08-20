import 'package:checkers/engine/checkers_engine.dart';
import 'package:checkers/engine/rules_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('piece counts start full and drop with captures', () {
    final engine = CheckersEngine(config: RulesConfig.international);
    expect(engine.pieceCount(PieceColor.white), 20);
    expect(engine.pieceCount(PieceColor.black), 20);

    // Play until the first capture happens (mandatory when available).
    var guard = 0;
    while (engine.pieceCount(PieceColor.white) == 20 &&
        engine.pieceCount(PieceColor.black) == 20 &&
        guard < 30) {
      engine.applyMove(engine.legalMoves().first);
      guard++;
    }
    expect(
      engine.pieceCount(PieceColor.white) + engine.pieceCount(PieceColor.black),
      lessThan(40),
    );
  });

  test('8x8 rules start with 12 pieces per side', () {
    final engine = CheckersEngine(config: RulesConfig.american);
    expect(engine.pieceCount(PieceColor.white), 12);
    expect(engine.pieceCount(PieceColor.black), 12);
  });
}
