import '../../engine/checkers_engine.dart';
import '../../engine/move.dart';
import '../../engine/rules_config.dart';

class OnlineGamePlayer {
  const OnlineGamePlayer({
    required this.uid,
    required this.seat,
    required this.nickname,
    this.photoUrl,
    this.color,
    this.connected = true,
    this.isBot = false,
    this.ratingBefore,
    this.ratingAfter,
  });

  /// Null for bot seats in streamed PC games.
  final String? uid;
  final int seat;
  final String nickname;
  final String? photoUrl;
  final PieceColor? color;
  final bool connected;
  final bool isBot;
  final int? ratingBefore;
  final int? ratingAfter;

  factory OnlineGamePlayer.fromJson(Map<String, dynamic> json) {
    return OnlineGamePlayer(
      uid: json['uid'] as String?,
      seat: (json['seat'] as num).toInt(),
      nickname: (json['nickname'] as String?) ?? '',
      photoUrl: json['photo_url'] as String?,
      color: switch (json['color'] as String?) {
        'white' => PieceColor.white,
        'black' => PieceColor.black,
        _ => null,
      },
      connected: (json['connected'] as bool?) ?? true,
      isBot: (json['is_bot'] as bool?) ?? false,
      ratingBefore: (json['rating_before'] as num?)?.toInt(),
      ratingAfter: (json['rating_after'] as num?)?.toInt(),
    );
  }
}

/// A spectator currently watching a game.
class GameWatcher {
  const GameWatcher({
    required this.uid,
    required this.nickname,
    this.photoUrl,
    required this.rating,
  });

  final String uid;
  final String nickname;
  final String? photoUrl;
  final int rating;

  factory GameWatcher.fromJson(Map<String, dynamic> json) {
    return GameWatcher(
      uid: json['uid'] as String,
      nickname: (json['nickname'] as String?) ?? '',
      photoUrl: json['photo_url'] as String?,
      rating: (json['rating'] as num?)?.toInt() ?? 1200,
    );
  }
}

/// Snapshot of the authoritative `games` row.
class OnlineGameSnapshot {
  const OnlineGameSnapshot({
    required this.id,
    required this.status,
    required this.rules,
    required this.ply,
    required this.sideToMove,
    required this.board,
    required this.whiteBankMs,
    required this.blackBankMs,
    this.turnStartedAt,
    this.turnDeadlineAt,
    this.lastMove,
    this.drawOfferColor,
    this.result,
    this.resultReason,
    this.winnerUid,
    this.rematchRequestedBy,
    this.rematchGameId,
    this.vsPc = false,
    this.aiLevel,
    this.allowUndo = false,
    this.players = const [],
  });

  final String id;
  final String status;
  final RulesConfig rules;
  final int ply;
  final PieceColor sideToMove;
  final List<int> board;
  final int whiteBankMs;
  final int blackBankMs;
  final DateTime? turnStartedAt;
  final DateTime? turnDeadlineAt;
  final Move? lastMove;
  final PieceColor? drawOfferColor;
  final String? result;
  final String? resultReason;
  final String? winnerUid;
  final String? rematchRequestedBy;
  final String? rematchGameId;
  final bool vsPc;
  final String? aiLevel;
  final bool allowUndo;
  final List<OnlineGamePlayer> players;

  bool get isPlaying => status == 'playing';
  bool get isFinished => status == 'finished' || status == 'abandoned';

  factory OnlineGameSnapshot.fromRow(
    Map<String, dynamic> row, {
    List<OnlineGamePlayer> players = const [],
  }) {
    final state = (row['state'] as Map?)?.cast<String, dynamic>();
    final lastMoveJson = (row['last_move'] as Map?)?.cast<String, dynamic>();
    return OnlineGameSnapshot(
      id: row['id'] as String,
      status: row['status'] as String,
      rules: RulesConfig(
        boardSize: (row['board_size'] as num).toInt(),
        backwardCapture: row['backward_capture'] as bool,
        flyingKing: row['flying_king'] as bool,
        majorityCapture: row['majority_capture'] as bool,
      ),
      ply: state == null ? 0 : ((state['ply'] as num?)?.toInt() ?? 0),
      sideToMove: state?['side'] == 'black' ? PieceColor.black : PieceColor.white,
      board: state == null
          ? const []
          : [for (final v in state['board'] as List) (v as num).toInt()],
      whiteBankMs: (row['white_bank_ms'] as num?)?.toInt() ?? 300000,
      blackBankMs: (row['black_bank_ms'] as num?)?.toInt() ?? 300000,
      turnStartedAt: row['turn_started_at'] == null
          ? null
          : DateTime.parse(row['turn_started_at'] as String),
      turnDeadlineAt: row['turn_deadline_at'] == null
          ? null
          : DateTime.parse(row['turn_deadline_at'] as String),
      lastMove: lastMoveJson == null ? null : Move.fromJson(lastMoveJson),
      drawOfferColor: switch (row['draw_offer_color'] as String?) {
        'white' => PieceColor.white,
        'black' => PieceColor.black,
        _ => null,
      },
      result: row['result'] as String?,
      resultReason: row['result_reason'] as String?,
      winnerUid: row['winner_uid'] as String?,
      rematchRequestedBy: row['rematch_requested_by'] as String?,
      rematchGameId: row['rematch_game_id'] as String?,
      vsPc: (row['vs_pc'] as bool?) ?? false,
      aiLevel: row['ai_level'] as String?,
      allowUndo: (row['allow_undo'] as bool?) ?? false,
      players: players,
    );
  }
}
