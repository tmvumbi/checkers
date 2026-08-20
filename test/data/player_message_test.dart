import 'package:checkers/data/models/player_message.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({
  String id = 'msg-1',
  String type = 'public',
  String language = 'en',
  Object? htmlText = '<b>Hello</b>',
  Object? imageUrl,
  Object? linkUrl,
  Object? targetUid,
  String publishAt = '2026-01-01T00:00:00Z',
  String expiresAt = '2027-01-01T00:00:00Z',
  bool enabled = true,
}) {
  return {
    'id': id,
    'type': type,
    'language': language,
    'html_text': htmlText,
    'image_url': imageUrl,
    'link_url': linkUrl,
    'target_uid': targetUid,
    'publish_at': publishAt,
    'expires_at': expiresAt,
    'enabled': enabled,
  };
}

void main() {
  group('PlayerMessage', () {
    test('parses a full row', () {
      final message = PlayerMessage.fromRow(
        _row(
          type: 'private',
          targetUid: 'uid-9',
          imageUrl: 'https://cdn.example/a.png',
          linkUrl: 'https://example.com',
        ),
      );
      expect(message.id, 'msg-1');
      expect(message.type, PlayerMessageType.private);
      expect(message.targetUid, 'uid-9');
      expect(message.hasText, isTrue);
      expect(message.hasImage, isTrue);
      expect(message.hasLink, isTrue);
      expect(message.language, 'en');
    });

    test('rejects rows without any content', () {
      expect(
        PlayerMessage.tryFromRow(_row(htmlText: null, imageUrl: null)),
        isNull,
      );
      expect(
        PlayerMessage.tryFromRow(_row(htmlText: '   ', imageUrl: null)),
        isNull,
      );
    });

    test('rejects unknown type and bad dates', () {
      expect(PlayerMessage.tryFromRow(_row(type: 'wat')), isNull);
      expect(PlayerMessage.tryFromRow(_row(publishAt: 'nope')), isNull);
    });

    test('active window respects publish, expiry, and enabled', () {
      final message = PlayerMessage.fromRow(_row());
      expect(message.isActiveAt(DateTime.utc(2026, 6, 1)), isTrue);
      expect(message.isActiveAt(DateTime.utc(2025, 12, 31)), isFalse);
      expect(message.isActiveAt(DateTime.utc(2027, 1, 2)), isFalse);

      final disabled = PlayerMessage.fromRow(_row(enabled: false));
      expect(disabled.isActiveAt(DateTime.utc(2026, 6, 1)), isFalse);
    });
  });
}
