import 'dart:async';

import 'package:get/get.dart';

import '../../../data/models/player_message.dart';
import '../../../services/player_message_service.dart';

class MessagesController extends GetxController {
  MessagesController({PlayerMessageService? playerMessageService})
    : _playerMessageService =
          playerMessageService ?? Get.find<PlayerMessageService>();

  final PlayerMessageService _playerMessageService;
  Worker? _messagesWorker;

  RxList<PlayerMessage> get messages => _playerMessageService.messages;

  @override
  void onReady() {
    super.onReady();
    unawaited(_playerMessageService.markVisibleMessagesRead());
    _messagesWorker = ever<List<PlayerMessage>>(
      _playerMessageService.messages,
      (_) => unawaited(_playerMessageService.markVisibleMessagesRead()),
    );
  }

  @override
  void onClose() {
    _messagesWorker?.dispose();
    super.onClose();
  }
}
