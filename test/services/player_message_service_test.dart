import 'dart:async';

import 'package:checkers/services/auth_service.dart';
import 'package:checkers/services/player_message_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAuthService extends Mock implements AuthService {}

Map<String, dynamic> _row(
  String id, {
  String type = 'public',
  String language = 'en',
  String? targetUid,
  String publishAt = '2026-01-01T00:00:00Z',
  String expiresAt = '2099-01-01T00:00:00Z',
  bool enabled = true,
}) {
  return {
    'id': id,
    'type': type,
    'language': language,
    'html_text': 'msg $id',
    'target_uid': targetUid,
    'publish_at': publishAt,
    'expires_at': expiresAt,
    'enabled': enabled,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthService auth;
  late StreamController<List<Map<String, dynamic>>> rows;
  late SupabasePlayerMessageService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = MockAuthService();
    rows = StreamController<List<Map<String, dynamic>>>.broadcast();
    when(() => auth.currentUser).thenReturn(
      const AuthUser(uid: 'uid-1', isAnonymous: true),
    );
    when(() => auth.userChanges).thenAnswer((_) => const Stream.empty());
    service = SupabasePlayerMessageService(
      authService: auth,
      rowsStreamFactory: () => rows.stream,
    );
    service.onInit();
  });

  tearDown(() async {
    service.onClose();
    await rows.close();
    Get.reset();
  });

  test('publishes active messages in the current language, newest first',
      () async {
    rows.add([
      _row('old', publishAt: '2026-01-01T00:00:00Z'),
      _row('new', publishAt: '2026-02-01T00:00:00Z'),
      _row('french', language: 'fr'),
      _row(
        'mine',
        type: 'private',
        targetUid: 'uid-1',
        publishAt: '2026-01-15T00:00:00Z',
      ),
      _row('expired', expiresAt: '2026-01-02T00:00:00Z'),
      _row('scheduled', publishAt: '2099-01-01T00:00:00Z'),
      _row('disabled', enabled: false),
    ]);
    await pumpEventQueue();

    expect(
      service.messages.map((m) => m.id).toList(),
      ['new', 'mine', 'old'],
    );
  });

  test('unread count drops to zero after marking messages read', () async {
    rows.add([_row('a'), _row('b')]);
    await pumpEventQueue();
    expect(service.unreadMessageCount.value, 2);

    await service.markVisibleMessagesRead();
    expect(service.unreadMessageCount.value, 0);

    // A new message arrives: only it counts as unread.
    rows.add([_row('a'), _row('b'), _row('c')]);
    await pumpEventQueue();
    expect(service.unreadMessageCount.value, 1);
  });

  test('read markers persist across resubscribes', () async {
    rows.add([_row('a')]);
    await pumpEventQueue();
    await service.markVisibleMessagesRead();

    // Language round-trip forces a full resubscribe + storage reload.
    service.setLanguage(const Locale('fr'));
    service.setLanguage(const Locale('en'));
    rows.add([_row('a')]);
    await pumpEventQueue();

    expect(service.unreadMessageCount.value, 0);
  });

  test('signed-out users see no messages', () async {
    when(() => auth.currentUser).thenReturn(null);
    service.setLanguage(const Locale('fr'));
    rows.add([_row('a', language: 'fr')]);
    await pumpEventQueue();

    expect(service.messages, isEmpty);
    expect(service.unreadMessageCount.value, 0);
  });
}
