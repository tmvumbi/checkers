import 'package:checkers/data/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserProfile', () {
    test('parses a full row', () {
      final profile = UserProfile.fromJson(const {
        'id': 'abc',
        'nickname': 'Marie',
        'photo_url': 'https://example.com/a.jpg',
        'is_anonymous': false,
        'rating': 1350,
        'rated_games': 12,
        'wins': 7,
        'losses': 3,
        'draws': 2,
      });

      expect(profile.uid, 'abc');
      expect(profile.nickname, 'Marie');
      expect(profile.photoUrl, 'https://example.com/a.jpg');
      expect(profile.isAnonymous, isFalse);
      expect(profile.rating, 1350);
      expect(profile.ratedGames, 12);
      expect(profile.wins, 7);
      expect(profile.losses, 3);
      expect(profile.draws, 2);
    });

    test('applies defaults for missing optional fields', () {
      final profile = UserProfile.fromJson(const {'id': 'abc'});
      expect(profile.nickname, '');
      expect(profile.rating, 1200);
      expect(profile.isAnonymous, isTrue);
    });

    test('upsert json contains only client-writable columns', () {
      const profile = UserProfile(uid: 'abc', nickname: 'Marie', rating: 1500);
      final json = profile.toUpsertJson();
      expect(json.keys, unorderedEquals(['id', 'nickname', 'photo_url', 'is_anonymous']));
    });

    test('copyWith can clear the photo', () {
      const profile = UserProfile(
        uid: 'abc',
        nickname: 'Marie',
        photoUrl: 'x',
      );
      expect(profile.copyWith(clearPhoto: true).photoUrl, isNull);
    });
  });
}
