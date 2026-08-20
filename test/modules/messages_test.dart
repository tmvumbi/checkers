import 'package:checkers/data/models/player_message.dart';
import 'package:checkers/main.dart';
import 'package:checkers/services/player_message_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class FakePlayerMessageService extends PlayerMessageService {
  @override
  final RxList<PlayerMessage> messages = <PlayerMessage>[].obs;
  @override
  final RxInt unreadMessageCount = 0.obs;

  int markReadCalls = 0;

  @override
  void setLanguage(Locale? locale) {}

  @override
  Future<void> markVisibleMessagesRead() async {
    markReadCalls += 1;
    unreadMessageCount.value = 0;
  }
}

class _TestBinding extends Bindings {
  _TestBinding(this.service);

  final PlayerMessageService service;

  @override
  void dependencies() {
    Get.put<PlayerMessageService>(service);
  }
}

PlayerMessage _message(String id, {String? linkUrl}) {
  return PlayerMessage(
    id: id,
    type: PlayerMessageType.public,
    language: 'en',
    htmlText: '<b>Welcome to Checkers!</b>',
    linkUrl: linkUrl,
    publishAt: DateTime.utc(2026),
    expiresAt: DateTime.utc(2099),
    enabled: true,
  );
}

void main() {
  tearDown(Get.reset);

  testWidgets('shows the empty state without messages', (tester) async {
    await tester.pumpWidget(
      CheckersApp(
        initialBinding: _TestBinding(FakePlayerMessageService()),
        initialRoute: '/messages',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('messages-empty')), findsOneWidget);
  });

  testWidgets('renders message cards and marks them read', (tester) async {
    final service = FakePlayerMessageService();
    service.messages.add(_message('m1'));
    service.unreadMessageCount.value = 1;

    await tester.pumpWidget(
      CheckersApp(
        initialBinding: _TestBinding(service),
        initialRoute: '/messages',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-message-m1')), findsOneWidget);
    expect(find.textContaining('Welcome to Checkers!'), findsOneWidget);
    expect(service.markReadCalls, greaterThan(0));
    expect(service.unreadMessageCount.value, 0);
  });
}
