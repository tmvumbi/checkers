import 'package:checkers/data/models/online_game.dart';
import 'package:checkers/engine/checkers_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snapshot parses streamed PC game fields and bot seats', () {
    final snapshot = OnlineGameSnapshot.fromRow(
      {
        'id': 'g1',
        'status': 'playing',
        'board_size': 8,
        'backward_capture': false,
        'flying_king': false,
        'majority_capture': false,
        'vs_pc': true,
        'ai_level': 'hard',
        'allow_undo': true,
        'white_bank_ms': 300000,
        'black_bank_ms': 300000,
        'state': {
          'ply': 0,
          'side': 'white',
          'board': [for (var i = 0; i < 32; i++) 0],
        },
      },
      players: const [
        OnlineGamePlayer(uid: 'u1', seat: 0, nickname: 'Human'),
        OnlineGamePlayer(
          uid: null,
          seat: 1,
          nickname: 'PC',
          isBot: true,
          color: PieceColor.black,
        ),
      ],
    );
    expect(snapshot.vsPc, isTrue);
    expect(snapshot.aiLevel, 'hard');
    expect(snapshot.allowUndo, isTrue);
    expect(snapshot.players[1].isBot, isTrue);
    expect(snapshot.players[1].uid, isNull);
  });

  test('bot player rows parse with null uid', () {
    final player = OnlineGamePlayer.fromJson(const {
      'uid': null,
      'seat': 1,
      'nickname': 'PC',
      'is_bot': true,
      'color': 'black',
    });
    expect(player.isBot, isTrue);
    expect(player.uid, isNull);
    expect(player.color, PieceColor.black);
  });

  test('GameWatcher parses with defaults', () {
    final watcher = GameWatcher.fromJson(const {
      'uid': 'w1',
      'nickname': 'Spec',
      'photo_url': null,
      'rating': 1250,
    });
    expect(watcher.nickname, 'Spec');
    expect(watcher.rating, 1250);
  });
}
