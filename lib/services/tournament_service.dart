import 'package:dartvex/dartvex.dart' show ConvexException;
import 'package:get/get.dart';

import '../core/network/api_result.dart';
import '../data/models/tournament.dart';
import 'convex/convex_gateway.dart';

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

class ConvexTournamentService implements TournamentService {
  ConvexTournamentService({ConvexGateway? gateway})
    : _gatewayOverride = gateway;

  final ConvexGateway? _gatewayOverride;
  ConvexGateway get _convex => _gatewayOverride ?? Get.find<ConvexGateway>();

  Future<ApiResult<void>> _call(
    String name, [
    Map<String, dynamic> args = const {},
  ]) => guardConvex(() async {
    await _convex.mutation(name, args);
  });

  @override
  Future<ApiResult<void>> joinLobby() => _call('tournaments:joinLobby');

  @override
  Future<ApiResult<void>> touchLobby() => _call('tournaments:touchLobby');

  @override
  Future<ApiResult<void>> leaveLobby() => _call('tournaments:leaveLobby');

  @override
  Future<ApiResult<void>> optInNotify(String fcmToken) =>
      _call('tournaments:optInNotify', {'token': fcmToken});

  @override
  Future<ApiResult<void>> cancelNotify() => _call('tournaments:cancelNotify');

  @override
  Stream<List<TournamentLobbyPlayer>> watchLobby() {
    return _convex.watch('tournaments:lobby').map((rows) {
      final players = [
        for (final row in asRows(rows)) TournamentLobbyPlayer.fromJson(row),
      ]..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
      return players;
    });
  }

  @override
  Future<ApiResult<MyTournamentState>> myTournamentState() => guardConvex(
    () async => MyTournamentState.fromJson(
      asRow(await _convex.query('tournaments:myState')),
    ),
  );

  @override
  Future<ApiResult<List<TournamentSummary>>> fetchTournaments({
    required int offset,
    required int limit,
  }) {
    return guardConvex(() async {
      final rows = asRows(
        await _convex.query('tournaments:list', {
          'offset': offset,
          'limit': limit,
        }),
      );
      return [for (final row in rows) TournamentSummary.fromJson(row)];
    });
  }

  @override
  Future<ApiResult<TournamentDetail>> fetchTournamentDetail(String id) {
    return guardConvex(() async {
      final response = await _convex.query('tournaments:detail', {
        'tournamentId': id,
      });
      if (response == null) {
        throw ConvexException(
          'tournament_not_found',
          data: 'tournament_not_found',
        );
      }
      final detail = asRow(response);
      return TournamentDetail(
        summary: TournamentSummary.fromJson(asRow(detail['tournament'])),
        players: [
          for (final row in asRows(detail['players']))
            TournamentPlayer.fromJson(row),
        ],
        matches: [
          for (final row in asRows(detail['matches']))
            TournamentMatch.fromJson(row),
        ],
      );
    });
  }

  @override
  Stream<List<TournamentMatch>> watchMatches(String tournamentId) {
    return _convex
        .watch('tournaments:matches', {'tournamentId': tournamentId})
        .map(
          (rows) => [
            for (final row in asRows(rows)) TournamentMatch.fromJson(row),
          ],
        );
  }
}
