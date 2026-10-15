import 'dart:async';

import 'package:dartvex/dartvex.dart' show ConvexException;
import 'package:get/get.dart';

import '../core/network/api_result.dart';
import '../data/models/online_game.dart';
import '../engine/checkers_engine.dart';
import '../engine/move.dart';
import '../engine/rules_config.dart';
import 'convex/convex_gateway.dart';

class LeaderboardPlayer {
  const LeaderboardPlayer({
    required this.uid,
    required this.nickname,
    this.photoUrl,
    required this.rating,
    this.points = 0,
    required this.ratedGames,
    required this.wins,
    required this.losses,
    required this.draws,
  });

  final String uid;
  final String nickname;
  final String? photoUrl;
  final int rating;
  final int points;
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
      points: (json['points'] as num?)?.toInt() ?? 0,
      ratedGames: (json['rated_games'] as num?)?.toInt() ?? 0,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      losses: (json['losses'] as num?)?.toInt() ?? 0,
      draws: (json['draws'] as num?)?.toInt() ?? 0,
    );
  }
}

class PointRules {
  const PointRules({
    this.pcEasyWin = 1,
    this.pcMediumWin = 5,
    this.pcHardWin = 10,
    this.tournamentPerParticipant = 1,
    this.tournamentBonus = 0,
  });

  final int pcEasyWin;
  final int pcMediumWin;
  final int pcHardWin;
  final int tournamentPerParticipant;
  final int tournamentBonus;

  factory PointRules.fromJson(Map<String, dynamic> json) {
    return PointRules(
      pcEasyWin: (json['pc_easy_win'] as num?)?.toInt() ?? 1,
      pcMediumWin: (json['pc_medium_win'] as num?)?.toInt() ?? 5,
      pcHardWin: (json['pc_hard_win'] as num?)?.toInt() ?? 10,
      tournamentPerParticipant:
          (json['tournament_per_participant'] as num?)?.toInt() ?? 1,
      tournamentBonus: (json['tournament_bonus'] as num?)?.toInt() ?? 0,
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
  Future<ApiResult<List<LeaderboardPlayer>>> fetchPointsLeaderboard();
  Future<ApiResult<PointRules>> fetchPointRules();
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

class ConvexOnlineGameService implements OnlineGameService {
  ConvexOnlineGameService({ConvexGateway? gateway})
    : _gatewayOverride = gateway;

  final ConvexGateway? _gatewayOverride;
  ConvexGateway get _convex => _gatewayOverride ?? Get.find<ConvexGateway>();

  OnlineGameSnapshot _snapshot(Map<String, dynamic> row) {
    return OnlineGameSnapshot.fromRow(
      row,
      players: [
        for (final playerRow in asRows(row['game_players']))
          OnlineGamePlayer.fromJson(playerRow),
      ]..sort((a, b) => a.seat.compareTo(b.seat)),
    );
  }

  List<OnlineGameSnapshot> _snapshots(Object? rows) => [
    for (final row in asRows(rows)) _snapshot(row),
  ];

  List<LeaderboardPlayer> _leaders(Object? rows) => [
    for (final row in asRows(rows)) LeaderboardPlayer.fromJson(row),
  ];

  Future<ApiResult<void>> _call(String name, Map<String, dynamic> args) =>
      guardConvex(() async {
        await _convex.mutation(name, args);
      });

  @override
  Future<ApiResult<({String gameId, int seat})>> joinOnlineGame(String preset) {
    return guardConvex(() async {
      final map = asRow(
        await _convex.mutation('games:joinOnlineGame', {'preset': preset}),
      );
      return (
        gameId: map['game_id'] as String,
        seat: (map['seat'] as num).toInt(),
      );
    });
  }

  @override
  Future<ApiResult<OnlineGameSnapshot>> fetchGame(String gameId) {
    return guardConvex(() async {
      final row = await _convex.query('games:get', {'gameId': gameId});
      if (row == null) {
        throw ConvexException('game_not_found', data: 'game_not_found');
      }
      return _snapshot(asRow(row));
    });
  }

  @override
  Stream<OnlineGameSnapshot> watchGame(String gameId) {
    return _convex.watch('games:get', {'gameId': gameId}).map((row) {
      if (row == null) {
        throw StateError('game_disappeared');
      }
      return _snapshot(asRow(row));
    });
  }

  @override
  Future<ApiResult<void>> submitMove(
    String gameId,
    Move move,
    int expectedPly,
  ) => _call('games:submitMove', {
    'gameId': gameId,
    'move': move.toJson(),
    'expectedPly': expectedPly,
  });

  @override
  Future<ApiResult<void>> claimTimeout(String gameId) =>
      _call('games:claimTimeout', {'gameId': gameId});

  @override
  Future<ApiResult<void>> resignGame(String gameId) =>
      _call('games:resignGame', {'gameId': gameId});

  @override
  Future<ApiResult<void>> leaveGame(String gameId) =>
      _call('games:leaveGame', {'gameId': gameId});

  @override
  Future<ApiResult<void>> touchConnection(String gameId, bool connected) =>
      _call('games:touchConnection', {
        'gameId': gameId,
        'connected': connected,
      });

  @override
  Future<ApiResult<List<Move>>> fetchMoves(String gameId) {
    return guardConvex(() async {
      final rows = asRows(
        await _convex.query('games:moves', {'gameId': gameId}),
      );
      return [for (final row in rows) Move.fromJson(asRow(row['move']))];
    });
  }

  @override
  Future<ApiResult<List<OnlineGameSnapshot>>> fetchWatchableGames({
    int offset = 0,
    int limit = 30,
  }) {
    return guardConvex(
      () async => _snapshots(
        await _convex.query('games:watchable', {
          'offset': offset,
          'limit': limit,
        }),
      ),
    );
  }

  @override
  Future<ApiResult<ResumableGame?>> fetchMyActiveGame() {
    return guardConvex(() async {
      final response = await _convex.query('games:myActiveGame');
      return response == null ? null : ResumableGame.fromJson(asRow(response));
    });
  }

  @override
  Future<ApiResult<List<OnlineGameSnapshot>>> fetchRecentGames({
    String? search,
    bool mine = false,
    int offset = 0,
    int limit = 10,
  }) {
    return guardConvex(
      () async => _snapshots(
        await _convex.query('games:recent', {
          'search': search,
          'mine': mine,
          'offset': offset,
          'limit': limit,
        }),
      ),
    );
  }

  @override
  Future<ApiResult<List<LeaderboardPlayer>>> fetchLeaderboard() => guardConvex(
    () async => _leaders(await _convex.query('games:leaderboard')),
  );

  @override
  Future<ApiResult<List<LeaderboardPlayer>>> fetchPointsLeaderboard() =>
      guardConvex(
        () async => _leaders(await _convex.query('games:pointsLeaderboard')),
      );

  @override
  Future<ApiResult<PointRules>> fetchPointRules() => guardConvex(
    () async =>
        PointRules.fromJson(asRow(await _convex.query('games:pointRules'))),
  );

  @override
  Future<ApiResult<String>> startPcGame({
    required RulesConfig rules,
    required String aiLevel,
    required bool allowUndo,
    required String humanColor,
  }) {
    return guardConvex(() async {
      final response = asRow(
        await _convex.mutation('pcGames:start', {
          'boardSize': rules.boardSize,
          'backwardCapture': rules.backwardCapture,
          'flyingKing': rules.flyingKing,
          'majorityCapture': rules.majorityCapture,
          'aiLevel': aiLevel,
          'allowUndo': allowUndo,
          'humanColor': humanColor,
        }),
      );
      return response['game_id'] as String;
    });
  }

  @override
  Future<ApiResult<void>> submitPcMove(
    String gameId,
    Move move,
    int expectedPly,
  ) => _call('pcGames:submitMove', {
    'gameId': gameId,
    'move': move.toJson(),
    'expectedPly': expectedPly,
  });

  @override
  Future<ApiResult<void>> undoPcMoves(String gameId, int count) =>
      _call('pcGames:undoMoves', {'gameId': gameId, 'count': count});

  @override
  Future<ApiResult<void>> watchHeartbeat(String gameId) =>
      _call('watch:heartbeat', {'gameId': gameId});

  @override
  Future<ApiResult<void>> unwatchGame(String gameId) =>
      _call('watch:unwatch', {'gameId': gameId});

  @override
  Future<ApiResult<void>> sendEmote(String gameId, String emoji) =>
      _call('watch:sendEmote', {'gameId': gameId, 'emoji': emoji});

  @override
  Stream<List<GameEmote>> watchEmotes(String gameId) {
    return _convex.watch('watch:emotes', {'gameId': gameId}).map((rows) {
      final emotes = [for (final row in asRows(rows)) GameEmote.fromJson(row)];
      emotes.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return emotes;
    });
  }

  @override
  Stream<List<GameWatcher>> watchWatchers(String gameId) {
    return _convex.watch('watch:watchers', {'gameId': gameId}).map((rows) {
      final watchers = [
        for (final row in asRows(rows)) GameWatcher.fromJson(row),
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
    return guardConvex(() async {
      final rows = asRows(
        await _convex.query('watch:watchers', {
          'gameId': gameId,
          'offset': offset,
          'limit': limit,
        }),
      );
      return [for (final row in rows) GameWatcher.fromJson(row)];
    });
  }

  @override
  Future<ApiResult<void>> offerDraw(String gameId) =>
      _call('games:offerDraw', {'gameId': gameId});

  @override
  Future<ApiResult<void>> respondDraw(String gameId, bool accept) =>
      _call('games:respondDraw', {'gameId': gameId, 'accept': accept});

  @override
  Future<ApiResult<({String status, String? gameId})>> requestRematch(
    String gameId,
  ) {
    return guardConvex(() async {
      final map = asRow(
        await _convex.mutation('games:requestRematch', {'gameId': gameId}),
      );
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
      final response = await _convex.mutation('games:serverTime');
      final after = DateTime.now();
      final serverNow = DateTime.parse(response as String);
      final midpoint = before.add(after.difference(before) ~/ 2);
      return serverNow.difference(midpoint).inMilliseconds;
    } catch (_) {
      return 0;
    }
  }
}
