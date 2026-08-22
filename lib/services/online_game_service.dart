import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/api_error.dart';
import '../core/network/api_result.dart';
import '../data/models/online_game.dart';
import '../engine/checkers_engine.dart';
import '../engine/move.dart';
import '../engine/rules_config.dart';

class LeaderboardPlayer {
  const LeaderboardPlayer({
    required this.uid,
    required this.nickname,
    this.photoUrl,
    required this.rating,
    required this.ratedGames,
    required this.wins,
    required this.losses,
    required this.draws,
  });

  final String uid;
  final String nickname;
  final String? photoUrl;
  final int rating;
  final int ratedGames;
  final int wins;
  final int losses;
  final int draws;

  factory LeaderboardPlayer.fromJson(Map<String, dynamic> json) {
    return LeaderboardPlayer(
      uid: json['uid'] as String,
      nickname: (json['nickname'] as String?) ?? '',
      photoUrl: json['photo_url'] as String?,
      rating: (json['rating'] as num).toInt(),
      ratedGames: (json['rated_games'] as num?)?.toInt() ?? 0,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      losses: (json['losses'] as num?)?.toInt() ?? 0,
      draws: (json['draws'] as num?)?.toInt() ?? 0,
    );
  }
}

class GameEmote {
  const GameEmote({
    required this.id,
    required this.uid,
    required this.emoji,
    required this.createdAt,
  });

  final String id;
  final String uid;
  final String emoji;
  final DateTime createdAt;

  factory GameEmote.fromJson(Map<String, dynamic> json) {
    return GameEmote(
      id: json['id'] as String,
      uid: json['uid'] as String,
      emoji: (json['emoji'] as String?) ?? '',
      createdAt:
          DateTime.tryParse((json['created_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}

/// An online game this player is still seated at, found on a cold start so
/// the game survives the app being killed (PRD §6.4).
class ResumableGame {
  const ResumableGame({
    required this.gameId,
    required this.rules,
    required this.humanColor,
    required this.opponentNickname,
    required this.myTurn,
    this.tournamentId,
  });

  final String gameId;
  final RulesConfig rules;
  final PieceColor humanColor;
  final String opponentNickname;
  final bool myTurn;

  /// Set when the game in progress is a tournament match, so resuming it
  /// behaves like entering from the bracket.
  final String? tournamentId;

  static ResumableGame? fromJson(Map<String, dynamic> json) {
    final color = json['color'] as String?;
    final gameId = json['game_id'] as String?;
    if (gameId == null || (color != 'white' && color != 'black')) {
      return null;
    }
    return ResumableGame(
      gameId: gameId,
      rules: RulesConfig(
        boardSize: (json['board_size'] as num).toInt(),
        backwardCapture: json['backward_capture'] as bool,
        flyingKing: json['flying_king'] as bool,
        majorityCapture: json['majority_capture'] as bool,
      ),
      humanColor: color == 'white' ? PieceColor.white : PieceColor.black,
      opponentNickname: (json['opponent_nickname'] as String?) ?? '',
      myTurn: (json['my_turn'] as bool?) ?? false,
      tournamentId: json['tournament_id'] as String?,
    );
  }
}

abstract class OnlineGameService {
  Future<ApiResult<({String gameId, int seat})>> joinOnlineGame(String preset);

  /// The in-progress human game this player is seated at, if any.
  Future<ApiResult<ResumableGame?>> fetchMyActiveGame();
  Future<ApiResult<List<OnlineGameSnapshot>>> fetchWatchableGames({
    int offset,
    int limit,
  });
  Future<ApiResult<List<OnlineGameSnapshot>>> fetchRecentGames({
    String? search,
    bool mine,
    int offset,
    int limit,
  });
  Future<ApiResult<List<LeaderboardPlayer>>> fetchLeaderboard();
  Future<ApiResult<OnlineGameSnapshot>> fetchGame(String gameId);
  Stream<OnlineGameSnapshot> watchGame(String gameId);
  Future<ApiResult<void>> submitMove(String gameId, Move move, int expectedPly);
  Future<ApiResult<void>> claimTimeout(String gameId);
  Future<ApiResult<void>> resignGame(String gameId);
  Future<ApiResult<void>> leaveGame(String gameId);
  Future<ApiResult<void>> touchConnection(String gameId, bool connected);
  Future<ApiResult<List<Move>>> fetchMoves(String gameId);

  // Streamed PC games (PRD update: visible in Watch when signed in).
  Future<ApiResult<String>> startPcGame({
    required RulesConfig rules,
    required String aiLevel,
    required bool allowUndo,
    required String humanColor,
  });
  Future<ApiResult<void>> submitPcMove(
    String gameId,
    Move move,
    int expectedPly,
  );
  Future<ApiResult<void>> undoPcMoves(String gameId, int count);

  // In-game emoji exchanges.
  Future<ApiResult<void>> sendEmote(String gameId, String emoji);
  Stream<List<GameEmote>> watchEmotes(String gameId);

  // Spectator presence.
  Future<ApiResult<void>> watchHeartbeat(String gameId);
  Future<ApiResult<void>> unwatchGame(String gameId);
  Stream<List<GameWatcher>> watchWatchers(String gameId);
  Future<ApiResult<List<GameWatcher>>> fetchWatchers(
    String gameId, {
    required int offset,
    required int limit,
  });

  Future<ApiResult<void>> offerDraw(String gameId);
  Future<ApiResult<void>> respondDraw(String gameId, bool accept);
  Future<ApiResult<({String status, String? gameId})>> requestRematch(
    String gameId,
  );

  /// Milliseconds to ADD to local clock to approximate server time.
  Future<int> serverTimeOffsetMs();
}

class SupabaseOnlineGameService implements OnlineGameService {
  SupabaseOnlineGameService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<ApiResult<T>> _guard<T>(Future<T> Function() action) async {
    try {
      return Success(await action());
    } on PostgrestException catch (error) {
      return Failure(
        ApiError(code: error.message, message: error.message),
      );
    } catch (error) {
      return Failure(ApiError(code: 'unknown', message: error.toString()));
    }
  }

  @override
  Future<ApiResult<({String gameId, int seat})>> joinOnlineGame(
    String preset,
  ) {
    return _guard(() async {
      final response = await _client.rpc<dynamic>(
        'join_online_game',
        params: {'p_preset': preset},
      );
      final map = (response as Map).cast<String, dynamic>();
      return (
        gameId: map['game_id'] as String,
        seat: (map['seat'] as num).toInt(),
      );
    });
  }

  Future<List<OnlineGamePlayer>> _players(String gameId) async {
    final rows = await _client
        .from('game_players')
        .select()
        .eq('game_id', gameId)
        .order('seat', ascending: true);
    return [
      for (final row in rows) OnlineGamePlayer.fromJson(row),
    ];
  }

  @override
  Future<ApiResult<OnlineGameSnapshot>> fetchGame(String gameId) {
    return _guard(() async {
      final row = await _client
          .from('games')
          .select()
          .eq('id', gameId)
          .single();
      return OnlineGameSnapshot.fromRow(row, players: await _players(gameId));
    });
  }

  @override
  Stream<OnlineGameSnapshot> watchGame(String gameId) {
    // Player rows change rarely; refresh them on each games-row event.
    return _client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .asyncMap((rows) async {
          if (rows.isEmpty) {
            throw StateError('game_disappeared');
          }
          return OnlineGameSnapshot.fromRow(
            rows.first,
            players: await _players(gameId),
          );
        });
  }

  @override
  Future<ApiResult<void>> submitMove(
    String gameId,
    Move move,
    int expectedPly,
  ) {
    return _guard(() async {
      await _client.rpc<dynamic>('submit_move', params: {
        'p_game_id': gameId,
        'p_move': move.toJson(),
        'p_expected_ply': expectedPly,
      });
    });
  }

  @override
  Future<ApiResult<void>> claimTimeout(String gameId) {
    return _guard(
      () => _client.rpc<dynamic>('claim_timeout', params: {'p_game_id': gameId}),
    );
  }

  @override
  Future<ApiResult<void>> resignGame(String gameId) {
    return _guard(
      () => _client.rpc<dynamic>('resign_game', params: {'p_game_id': gameId}),
    );
  }

  @override
  Future<ApiResult<void>> leaveGame(String gameId) {
    return _guard(
      () => _client.rpc<dynamic>('leave_game', params: {'p_game_id': gameId}),
    );
  }

  @override
  Future<ApiResult<void>> touchConnection(String gameId, bool connected) {
    return _guard(
      () => _client.rpc<dynamic>('touch_game_connection', params: {
        'p_game_id': gameId,
        'p_connected': connected,
      }),
    );
  }

  @override
  Future<ApiResult<List<Move>>> fetchMoves(String gameId) {
    return _guard(() async {
      final rows = await _client
          .from('game_moves')
          .select('ply, move')
          .eq('game_id', gameId)
          .order('ply', ascending: true);
      return [
        for (final row in rows)
          Move.fromJson((row['move'] as Map).cast<String, dynamic>()),
      ];
    });
  }

  @override
  Future<ApiResult<List<OnlineGameSnapshot>>> fetchWatchableGames({
    int offset = 0,
    int limit = 30,
  }) {
    return _guard(() async {
      // Private games are listed too (migration 0030 opened the select
      // policy); every live game is watchable.
      final rows = await _client
          .from('games')
          .select('*, game_players(*)')
          .eq('status', 'playing')
          .order('started_at', ascending: false)
          .range(offset, offset + limit - 1);
      return [for (final row in rows) _snapshotWithPlayers(row)];
    });
  }

  @override
  Future<ApiResult<ResumableGame?>> fetchMyActiveGame() {
    return _guard(() async {
      final response = await _client.rpc<dynamic>('my_active_game');
      if (response == null) {
        return null;
      }
      return ResumableGame.fromJson((response as Map).cast<String, dynamic>());
    });
  }

  @override
  Future<ApiResult<List<OnlineGameSnapshot>>> fetchRecentGames({
    String? search,
    bool mine = false,
    int offset = 0,
    int limit = 10,
  }) {
    return _guard(() async {
      final response = await _client.rpc<dynamic>(
        'list_recent_games',
        params: {
          'p_search': search,
          'p_mine': mine,
          'p_offset': offset,
          'p_limit': limit,
        },
      );
      return [
        for (final row in response as List)
          _snapshotWithPlayers((row as Map).cast<String, dynamic>()),
      ];
    });
  }

  OnlineGameSnapshot _snapshotWithPlayers(Map<String, dynamic> row) {
    return OnlineGameSnapshot.fromRow(
      row,
      players: [
        for (final playerRow in (row['game_players'] as List? ?? []))
          OnlineGamePlayer.fromJson((playerRow as Map).cast<String, dynamic>()),
      ]..sort((a, b) => a.seat.compareTo(b.seat)),
    );
  }

  @override
  Future<ApiResult<List<LeaderboardPlayer>>> fetchLeaderboard() {
    return _guard(() async {
      final response = await _client.rpc<dynamic>('get_leaderboard');
      return [
        for (final row in response as List)
          LeaderboardPlayer.fromJson((row as Map).cast<String, dynamic>()),
      ];
    });
  }

  @override
  Future<ApiResult<String>> startPcGame({
    required RulesConfig rules,
    required String aiLevel,
    required bool allowUndo,
    required String humanColor,
  }) {
    return _guard(() async {
      final response = await _client.rpc<dynamic>('start_pc_game', params: {
        'p_board_size': rules.boardSize,
        'p_backward_capture': rules.backwardCapture,
        'p_flying_king': rules.flyingKing,
        'p_majority_capture': rules.majorityCapture,
        'p_ai_level': aiLevel,
        'p_allow_undo': allowUndo,
        'p_human_color': humanColor,
      });
      return (response as Map)['game_id'] as String;
    });
  }

  @override
  Future<ApiResult<void>> submitPcMove(
    String gameId,
    Move move,
    int expectedPly,
  ) {
    return _guard(
      () => _client.rpc<dynamic>('submit_pc_move', params: {
        'p_game_id': gameId,
        'p_move': move.toJson(),
        'p_expected_ply': expectedPly,
      }),
    );
  }

  @override
  Future<ApiResult<void>> undoPcMoves(String gameId, int count) {
    return _guard(
      () => _client.rpc<dynamic>('undo_pc_moves', params: {
        'p_game_id': gameId,
        'p_count': count,
      }),
    );
  }

  @override
  Future<ApiResult<void>> watchHeartbeat(String gameId) {
    return _guard(
      () => _client
          .rpc<dynamic>('watch_heartbeat', params: {'p_game_id': gameId}),
    );
  }

  @override
  Future<ApiResult<void>> unwatchGame(String gameId) {
    return _guard(
      () =>
          _client.rpc<dynamic>('unwatch_game', params: {'p_game_id': gameId}),
    );
  }

  @override
  Future<ApiResult<void>> sendEmote(String gameId, String emoji) {
    return _guard(() async {
      await _client.rpc<void>(
        'send_emote',
        params: {'p_game_id': gameId, 'p_emoji': emoji},
      );
    });
  }

  @override
  Stream<List<GameEmote>> watchEmotes(String gameId) {
    return _client
        .from('game_emotes')
        .stream(primaryKey: ['id'])
        .eq('game_id', gameId)
        .map((rows) {
          final emotes = [for (final row in rows) GameEmote.fromJson(row)];
          emotes.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return emotes;
        });
  }

  @override
  Stream<List<GameWatcher>> watchWatchers(String gameId) {
    return _client
        .from('game_watchers')
        .stream(primaryKey: ['game_id', 'uid'])
        .eq('game_id', gameId)
        .map((rows) {
          final watchers = [
            for (final row in rows) GameWatcher.fromJson(row),
          ];
          watchers.sort((a, b) => a.uid.compareTo(b.uid));
          return watchers;
        });
  }

  @override
  Future<ApiResult<List<GameWatcher>>> fetchWatchers(
    String gameId, {
    required int offset,
    required int limit,
  }) {
    return _guard(() async {
      final rows = await _client
          .from('game_watchers')
          .select()
          .eq('game_id', gameId)
          .order('joined_at', ascending: true)
          .range(offset, offset + limit - 1);
      return [for (final row in rows) GameWatcher.fromJson(row)];
    });
  }

  @override
  Future<ApiResult<void>> offerDraw(String gameId) {
    return _guard(
      () => _client.rpc<dynamic>('offer_draw', params: {'p_game_id': gameId}),
    );
  }

  @override
  Future<ApiResult<void>> respondDraw(String gameId, bool accept) {
    return _guard(
      () => _client.rpc<dynamic>('respond_draw', params: {
        'p_game_id': gameId,
        'p_accept': accept,
      }),
    );
  }

  @override
  Future<ApiResult<({String status, String? gameId})>> requestRematch(
    String gameId,
  ) {
    return _guard(() async {
      final response = await _client.rpc<dynamic>(
        'request_rematch',
        params: {'p_game_id': gameId},
      );
      final map = (response as Map).cast<String, dynamic>();
      return (
        status: map['status'] as String,
        gameId: map['game_id'] as String?,
      );
    });
  }

  @override
  Future<int> serverTimeOffsetMs() async {
    try {
      final before = DateTime.now();
      final response = await _client.rpc<dynamic>('server_time');
      final after = DateTime.now();
      final serverNow = DateTime.parse(response as String);
      final midpoint = before.add(after.difference(before) ~/ 2);
      return serverNow.difference(midpoint).inMilliseconds;
    } catch (_) {
      return 0;
    }
  }
}
