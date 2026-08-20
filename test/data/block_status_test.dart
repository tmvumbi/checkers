import 'package:checkers/data/models/block_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BlockStatus', () {
    test('null level means unblocked', () {
      final status = BlockStatus.fromJson({'level': null});
      expect(status.isBlocked, isFalse);
      expect(status.canPlay, isTrue);
      expect(status.canWatch, isTrue);
    });

    test('soft block allows watching but not playing', () {
      final status = BlockStatus.fromJson({
        'level': 'soft',
        'permanent': false,
        'expires_at': '2026-08-27T14:00:00Z',
      });
      expect(status.level, BlockLevel.soft);
      expect(status.canPlay, isFalse);
      expect(status.canWatch, isTrue);
      expect(status.permanent, isFalse);
      expect(status.expiresAt, isNotNull);
    });

    test('full block blocks watching too', () {
      final status = BlockStatus.fromJson({
        'level': 'full',
        'permanent': true,
        'expires_at': null,
      });
      expect(status.level, BlockLevel.full);
      expect(status.canPlay, isFalse);
      expect(status.canWatch, isFalse);
      expect(status.permanent, isTrue);
    });

    test('missing expiry falls back to permanent', () {
      final status = BlockStatus.fromJson({'level': 'full'});
      expect(status.permanent, isTrue);
    });
  });
}
