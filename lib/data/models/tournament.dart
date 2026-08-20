/// Tournament data models (read-only projections of the backend tables).
class TournamentSummary {
  const TournamentSummary({
    required this.id,
    required this.number,
    required this.status,
    required this.stage,
    required this.participantCount,
    required this.createdAt,
    this.winnerUid,
    this.winnerNickname,
    this.winnerPhotoUrl,
  });

  final String id;
  final int number;
  final String status; // elimination | knockout | finished
  final String stage; // elimination | r16... | qf | sf | f
  final int participantCount;
  final DateTime createdAt;
  final String? winnerUid;
  final String? winnerNickname;
  final String? winnerPhotoUrl;

  bool get isFinished => status == 'finished';

  factory TournamentSummary.fromJson(Map<String, dynamic> json) {
    return TournamentSummary(
      id: json['id'] as String,
      number: (json['number'] as num).toInt(),
      status: json['status'] as String,
      stage: json['stage'] as String,
      participantCount: (json['participant_count'] as num).toInt(),
      createdAt:
          DateTime.tryParse((json['created_at'] as String?) ?? '') ??
          DateTime.now(),
      winnerUid: json['winner_uid'] as String?,
      winnerNickname: json['winner_nickname'] as String?,
      winnerPhotoUrl: json['winner_photo_url'] as String?,
    );
  }

  TournamentSummary withWinner(String? nickname, String? photoUrl) {
    return TournamentSummary(
      id: id,
      number: number,
      status: status,
      stage: stage,
      participantCount: participantCount,
      createdAt: createdAt,
      winnerUid: winnerUid,
      winnerNickname: nickname,
      winnerPhotoUrl: photoUrl,
    );
  }
}

class TournamentPlayer {
  const TournamentPlayer({
    required this.uid,
    required this.nickname,
    required this.rating,
    required this.joinOrder,
    required this.points,
    required this.eliminated,
    this.photoUrl,
    this.finalRank,
  });

  final String uid;
  final String nickname;
  final String? photoUrl;
  final int rating;
  final int joinOrder;
  final int points;
  final bool eliminated;
  final int? finalRank;

  factory TournamentPlayer.fromJson(Map<String, dynamic> json) {
    return TournamentPlayer(
      uid: json['uid'] as String,
      nickname: (json['nickname'] as String?) ?? '',
      photoUrl: json['photo_url'] as String?,
      rating: (json['rating'] as num?)?.toInt() ?? 1200,
      joinOrder: (json['join_order'] as num?)?.toInt() ?? 0,
      points: (json['points'] as num?)?.toInt() ?? 0,
      eliminated: json['eliminated'] == true,
      finalRank: (json['final_rank'] as num?)?.toInt(),
    );
  }
}

class TournamentMatch {
  const TournamentMatch({
    required this.id,
    required this.stage,
    required this.matchIndex,
    required this.p1Uid,
    required this.p2Uid,
    required this.status,
    this.gameId,
    this.winnerUid,
  });

  final String id;
  final String stage;
  final int matchIndex;
  final String p1Uid;
  final String p2Uid;
  final String? gameId;
  final String? winnerUid;
  final String status; // playing | finished

  bool get isFinished => status == 'finished';

  factory TournamentMatch.fromJson(Map<String, dynamic> json) {
    return TournamentMatch(
      id: json['id'] as String,
      stage: json['stage'] as String,
      matchIndex: (json['match_index'] as num?)?.toInt() ?? 0,
      p1Uid: json['p1_uid'] as String,
      p2Uid: json['p2_uid'] as String,
      gameId: json['game_id'] as String?,
      winnerUid: json['winner_uid'] as String?,
      status: (json['status'] as String?) ?? 'playing',
    );
  }
}

class TournamentLobbyPlayer {
  const TournamentLobbyPlayer({
    required this.uid,
    required this.nickname,
    required this.rating,
    required this.joinedAt,
    this.photoUrl,
  });

  final String uid;
  final String nickname;
  final String? photoUrl;
  final int rating;
  final DateTime joinedAt;

  factory TournamentLobbyPlayer.fromJson(Map<String, dynamic> json) {
    return TournamentLobbyPlayer(
      uid: json['uid'] as String,
      nickname: (json['nickname'] as String?) ?? '',
      photoUrl: json['photo_url'] as String?,
      rating: (json['rating'] as num?)?.toInt() ?? 1200,
      joinedAt:
          DateTime.tryParse((json['joined_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}

class TournamentDetail {
  const TournamentDetail({
    required this.summary,
    required this.players,
    required this.matches,
  });

  final TournamentSummary summary;
  final List<TournamentPlayer> players;
  final List<TournamentMatch> matches;
}

class MyTournamentState {
  const MyTournamentState({this.tournamentId, this.gameId});

  final String? tournamentId;
  final String? gameId;

  factory MyTournamentState.fromJson(Map<String, dynamic> json) {
    return MyTournamentState(
      tournamentId: json['tournament_id'] as String?,
      gameId: json['game_id'] as String?,
    );
  }
}
