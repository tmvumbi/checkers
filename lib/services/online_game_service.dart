import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/api_error.dart';
import '../core/network/api_result.dart';
import '../data/models/online_game.dart';
import '../engine/move.dart';

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

abstract class OnlineGameService {
  Future<ApiResult<({String gameId, int seat})>> joinOnlineGame(String preset);
  Future<ApiResult<List<OnlineGameSnapshot>>> fetchWatchableGames();
  Future<ApiResult<List<LeaderboardPlayer>>> fetchLeaderboard();
  Future<ApiResult<OnlineGameSnapshot>> fetchGame(String gameId);
  Stream<OnlineGameSnapshot> watchGame(String gameId);
  Future<ApiResult<void>> submitMove(String gameId, Move move, int expectedPly);
  Future<ApiResult<void>> claimTimeout(String gameId);
  Future<ApiResult<void>> resignGame(String gameId);
  Future<ApiResult<void>> leaveGame(String gameId);
  Future<ApiResult<void>> touchConnection(String gameId, bool connected);
  Future<ApiResult<List<Move>>> fetchMoves(String gameId);

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
  Future<ApiResult<List<OnlineGameSnapshot>>> fetchWatchableGames() {
    return _guard(() async {
      final rows = await _client
          .from('games')
          .select('*, game_players(*)')
          .eq('status', 'playing')
          .eq('is_private', false)
          .order('started_at', ascending: false)
          .limit(30);
      return [
        for (final row in rows)
          OnlineGameSnapshot.fromRow(
            row,
            players: [
              for (final playerRow in (row['game_players'] as List? ?? []))
                OnlineGamePlayer.fromJson(
                  (playerRow as Map).cast<String, dynamic>(),
                ),
            ]..sort((a, b) => a.seat.compareTo(b.seat)),
          ),
      ];
    });
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
