class UserProfile {
  const UserProfile({
    required this.uid,
    required this.nickname,
    this.photoUrl,
    this.isAnonymous = true,
    this.rating = 1200,
    this.ratedGames = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
  });

  final String uid;
  final String nickname;
  final String? photoUrl;
  final bool isAnonymous;
  final int rating;
  final int ratedGames;
  final int wins;
  final int losses;
  final int draws;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      uid: json['id'] as String,
      nickname: (json['nickname'] as String?) ?? '',
      photoUrl: json['photo_url'] as String?,
      isAnonymous: (json['is_anonymous'] as bool?) ?? true,
      rating: (json['rating'] as num?)?.toInt() ?? 1200,
      ratedGames: (json['rated_games'] as num?)?.toInt() ?? 0,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      losses: (json['losses'] as num?)?.toInt() ?? 0,
      draws: (json['draws'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toUpsertJson() {
    return {
      'id': uid,
      'nickname': nickname,
      'photo_url': photoUrl,
      'is_anonymous': isAnonymous,
    };
  }

  UserProfile copyWith({
    String? nickname,
    String? photoUrl,
    bool clearPhoto = false,
    bool? isAnonymous,
    int? rating,
    int? ratedGames,
    int? wins,
    int? losses,
    int? draws,
  }) {
    return UserProfile(
      uid: uid,
      nickname: nickname ?? this.nickname,
      photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
      isAnonymous: isAnonymous ?? this.isAnonymous,
      rating: rating ?? this.rating,
      ratedGames: ratedGames ?? this.ratedGames,
      wins: wins ?? this.wins,
      losses: losses ?? this.losses,
      draws: draws ?? this.draws,
    );
  }
}
