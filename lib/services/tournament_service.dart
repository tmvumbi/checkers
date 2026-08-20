import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/api_error.dart';
import '../core/network/api_result.dart';
import '../data/models/tournament.dart';

abstract class TournamentService {
  Future<ApiResult<void>> joinLobby();
  Future<ApiResult<void>> touchLobby();
  Future<ApiResult<void>> leaveLobby();
  Future<ApiResult<void>> optInNotify(String fcmToken);
  Future<ApiResult<void>> cancelNotify();
  Stream<List<TournamentLobbyPlayer>> watchLobby();
  Future<ApiResult<MyTournamentState>> myTournamentState();
  Future<ApiResult<List<TournamentSummary>>> fetchTournaments({
    required int offset,
    required int limit,
  });
  Future<ApiResult<TournamentDetail>> fetchTournamentDetail(String id);
  Stream<List<TournamentMatch>> watchMatches(String tournamentId);
}

class SupabaseTournamentService implements TournamentService {
  SupabaseTournamentService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get client => _client ?? Supabase.instance.client;

  Future<ApiResult<T>> _guard<T>(Future<T> Function() action) async {
    try {
      return Success(await action());
    } on PostgrestException catch (error) {
      return Failure(ApiError(code: error.message, message: error.message));
    } catch (error) {
      return Failure(ApiError(code: 'unknown', message: error.toString()));
    }
  }

  @override
  Future<ApiResult<void>> joinLobby() {
    return _guard(
      () => client.rpc<void>('join_tournament_lobby'),
    );
  }

  @override
  Future<ApiResult<void>> touchLobby() {
    return _guard(() => client.rpc<void>('touch_tournament_lobby'));
  }

  @override
  Future<ApiResult<void>> leaveLobby() {
    return _guard(() => client.rpc<void>('leave_tournament_lobby'));
  }

  @override
  Future<ApiResult<void>> optInNotify(String fcmToken) {
    return _guard(
      () => client.rpc<void>(
        'opt_in_tournament_notify',
        params: {'p_token': fcmToken},
      ),
    );
  }

  @override
  Future<ApiResult<void>> cancelNotify() {
    return _guard(() => client.rpc<void>('cancel_tournament_notify'));
  }

  @override
  Stream<List<TournamentLobbyPlayer>> watchLobby() {
    return client.from('tournament_lobby').stream(primaryKey: ['uid']).map((
      rows,
    ) {
      // Dedupe defensively: the stream can briefly hold the initial
      // fetch and the realtime insert of the same row.
      final byUid = <String, TournamentLobbyPlayer>{
        for (final row in rows)
          row['uid'] as String: TournamentLobbyPlayer.fromJson(row),
      };
      final players = byUid.values.toList()
        ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
      return players;
    });
  }

  @override
  Future<ApiResult<MyTournamentState>> myTournamentState() {
    return _guard(() async {
      final response = await client.rpc<dynamic>('my_tournament_state');
      return MyTournamentState.fromJson(
        (response as Map).cast<String, dynamic>(),
      );
    });
  }

  @override
  Future<ApiResult<List<TournamentSummary>>> fetchTournaments({
    required int offset,
    required int limit,
  }) {
    return _guard(() async {
      final rows = await client
          .from('tournaments')
          .select()
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      var tournaments = [
        for (final row in rows) TournamentSummary.fromJson(row),
      ];

      // Attach winner identity for the finished ones.
      final finished = tournaments
          .where((t) => t.isFinished && t.winnerUid != null)
          .toList();
      if (finished.isNotEmpty) {
        final winnerRows = await client
            .from('tournament_players')
            .select('tournament_id, uid, nickname, photo_url')
            .inFilter('tournament_id', [
              for (final t in finished) t.id,
            ]);
        final winnersByTournament = <String, Map<String, dynamic>>{
          for (final row in winnerRows)
            '${row['tournament_id']}:${row['uid']}': row,
        };
        tournaments = [
          for (final t in tournaments)
            () {
              final winner = winnersByTournament['${t.id}:${t.winnerUid}'];
              return winner == null
                  ? t
                  : t.withWinner(
                      winner['nickname'] as String?,
                      winner['photo_url'] as String?,
                    );
            }(),
        ];
      }
      return tournaments;
    });
  }

  @override
  Future<ApiResult<TournamentDetail>> fetchTournamentDetail(String id) {
    return _guard(() async {
      final tournamentRow = await client
          .from('tournaments')
          .select()
          .eq('id', id)
          .single();
      final playerRows = await client
          .from('tournament_players')
          .select()
          .eq('tournament_id', id);
      final matchRows = await client
          .from('tournament_matches')
          .select()
          .eq('tournament_id', id)
          .order('created_at');
      return TournamentDetail(
        summary: TournamentSummary.fromJson(tournamentRow),
        players: [
          for (final row in playerRows) TournamentPlayer.fromJson(row),
        ],
        matches: [for (final row in matchRows) TournamentMatch.fromJson(row)],
      );
    });
  }

  @override
  Stream<List<TournamentMatch>> watchMatches(String tournamentId) {
    return client
        .from('tournament_matches')
        .stream(primaryKey: ['id'])
        .eq('tournament_id', tournamentId)
        .map(
          (rows) => [for (final row in rows) TournamentMatch.fromJson(row)],
        );
  }
}
