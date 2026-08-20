import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../data/models/player_message.dart';
import 'auth_service.dart';

/// Streams admin → player messages (kopo parity): public broadcasts plus
/// private messages for the signed-in player, in the active language, and
/// tracks a locally-persisted unread count.
abstract class PlayerMessageService extends GetxService {
  RxList<PlayerMessage> get messages;
  RxInt get unreadMessageCount;

  void setLanguage(Locale? locale);
  Future<void> markVisibleMessagesRead();
}

class SupabasePlayerMessageService extends PlayerMessageService {
  SupabasePlayerMessageService({
    AuthService? authService,
    Stream<List<Map<String, dynamic>>> Function()? rowsStreamFactory,
  }) : _authServiceOverride = authService,
       _rowsStreamFactoryOverride = rowsStreamFactory;

  static const String _readIdsStorageKeyPrefix = 'player_message_read_ids';

  final AuthService? _authServiceOverride;
  final Stream<List<Map<String, dynamic>>> Function()?
  _rowsStreamFactoryOverride;

  AuthService get _authService => _authServiceOverride ?? Get.find();

  @override
  final RxList<PlayerMessage> messages = <PlayerMessage>[].obs;
  @override
  final RxInt unreadMessageCount = 0.obs;

  final Map<String, PlayerMessage> _allMessages = <String, PlayerMessage>{};
  final Set<String> _readMessageIds = <String>{};
  StreamSubscription<AuthUser?>? _authSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _rowsSubscription;
  Timer? _activeWindowTimer;
  Future<void>? _readMessageIdsLoad;
  String _languageCode = 'en';
  bool _hasLoadedReadMessageIds = false;
  bool _hasReceivedSnapshot = false;
  int _readStateGeneration = 0;

  @override
  void onInit() {
    super.onInit();
    _languageCode = _languageCodeFor(Get.locale ?? Get.deviceLocale);
    _authSubscription = _authService.userChanges.listen((_) => _subscribe());
    _subscribe();
  }

  @override
  void onClose() {
    _authSubscription?.cancel();
    _rowsSubscription?.cancel();
    _activeWindowTimer?.cancel();
    super.onClose();
  }

  @override
  void setLanguage(Locale? locale) {
    final nextLanguageCode = _languageCodeFor(locale);
    if (_languageCode == nextLanguageCode) {
      return;
    }
    _languageCode = nextLanguageCode;
    _subscribe();
  }

  @override
  Future<void> markVisibleMessagesRead() async {
    final languageCode = _languageCode;
    final generation = _readStateGeneration;
    if (!_hasLoadedReadMessageIds) {
      await (_readMessageIdsLoad ??
          _loadReadMessageIds(languageCode, generation));
    }
    if (languageCode != _languageCode || generation != _readStateGeneration) {
      return;
    }

    final visibleMessageIds = messages.map((message) => message.id).toSet();
    if (visibleMessageIds.isEmpty) {
      return;
    }

    final previousLength = _readMessageIds.length;
    _readMessageIds.addAll(visibleMessageIds);
    if (_readMessageIds.length == previousLength) {
      _refreshUnreadMessageCount();
      return;
    }

    await _persistReadMessageIds(languageCode, Set<String>.of(_readMessageIds));
    _refreshUnreadMessageCount();
  }

  void _subscribe() {
    _rowsSubscription?.cancel();
    _rowsSubscription = null;
    _allMessages.clear();
    _hasReceivedSnapshot = false;
    _readStateGeneration += 1;
    _readMessageIds.clear();
    _hasLoadedReadMessageIds = false;
    unreadMessageCount.value = 0;
    _readMessageIdsLoad = _loadReadMessageIds(
      _languageCode,
      _readStateGeneration,
    );
    unawaited(_readMessageIdsLoad!);
    _publishActiveMessages();

    final user = _authService.currentUser;
    if (user == null) {
      return;
    }

    // Row-level security scopes rows to public + own private messages.
    _rowsSubscription = _rowsStream().listen(
      _handleRows,
      onError: (Object _) {
        _allMessages.clear();
        _hasReceivedSnapshot = false;
        _publishActiveMessages();
      },
    );
  }

  Stream<List<Map<String, dynamic>>> _rowsStream() {
    final factory = _rowsStreamFactoryOverride;
    if (factory != null) {
      return factory();
    }
    return Supabase.instance.client
        .from('player_messages')
        .stream(primaryKey: ['id']);
  }

  void _handleRows(List<Map<String, dynamic>> rows) {
    _allMessages.clear();
    for (final row in rows) {
      final message = PlayerMessage.tryFromRow(row);
      if (message != null && message.language == _languageCode) {
        _allMessages[message.id] = message;
      }
    }
    _hasReceivedSnapshot = true;
    _publishActiveMessages();
    unawaited(_pruneReadMessageIdsIfReady());
  }

  void _publishActiveMessages() {
    final now = DateTime.now().toUtc();
    final activeMessages =
        _allMessages.values
            .where((message) => message.isActiveAt(now))
            .toList(growable: false)
          ..sort((left, right) => right.publishAt.compareTo(left.publishAt));
    messages.assignAll(activeMessages);
    _refreshUnreadMessageCount();
    _scheduleActiveWindowRefresh(_allMessages.values, now);
  }

  Future<void> _loadReadMessageIds(String languageCode, int generation) async {
    final Set<String> storedIds;
    try {
      final preferences = await SharedPreferences.getInstance();
      storedIds =
          (preferences.getStringList(_readIdsStorageKey(languageCode)) ??
                  const <String>[])
              .where((id) => id.trim().isNotEmpty)
              .toSet();
    } catch (_) {
      return;
    }
    if (generation != _readStateGeneration || languageCode != _languageCode) {
      return;
    }

    _readMessageIds
      ..clear()
      ..addAll(storedIds);
    _hasLoadedReadMessageIds = true;
    _refreshUnreadMessageCount();
    await _pruneReadMessageIdsIfReady();
  }

  /// Drops read markers for messages that no longer exist, so storage
  /// doesn't grow forever.
  Future<void> _pruneReadMessageIdsIfReady() async {
    if (!_hasLoadedReadMessageIds || !_hasReceivedSnapshot) {
      return;
    }

    final languageCode = _languageCode;
    final activeMessageIds = messages.map((message) => message.id).toSet();
    final previousLength = _readMessageIds.length;
    _readMessageIds.removeWhere((id) => !activeMessageIds.contains(id));
    if (_readMessageIds.length == previousLength) {
      return;
    }

    await _persistReadMessageIds(languageCode, Set<String>.of(_readMessageIds));
    _refreshUnreadMessageCount();
  }

  Future<void> _persistReadMessageIds(
    String languageCode,
    Set<String> messageIds,
  ) async {
    final sortedIds = messageIds.toList(growable: false)..sort();
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList(
        _readIdsStorageKey(languageCode),
        sortedIds,
      );
    } catch (_) {}
  }

  void _refreshUnreadMessageCount() {
    if (!_hasLoadedReadMessageIds) {
      unreadMessageCount.value = 0;
      return;
    }

    unreadMessageCount.value = messages
        .where((message) => !_readMessageIds.contains(message.id))
        .length;
  }

  String _readIdsStorageKey(String languageCode) {
    return '${_readIdsStorageKeyPrefix}_$languageCode';
  }

  /// Re-evaluates the active set when the next message enters or leaves
  /// its publish window.
  void _scheduleActiveWindowRefresh(
    Iterable<PlayerMessage> allMessages,
    DateTime now,
  ) {
    _activeWindowTimer?.cancel();
    DateTime? nextBoundary;
    for (final message in allMessages) {
      final boundary = message.publishAt.isAfter(now)
          ? message.publishAt
          : message.expiresAt.isAfter(now)
          ? message.expiresAt
          : null;
      if (boundary != null &&
          (nextBoundary == null || boundary.isBefore(nextBoundary))) {
        nextBoundary = boundary;
      }
    }
    if (nextBoundary == null) {
      return;
    }
    final delay = nextBoundary.difference(now) + const Duration(seconds: 1);
    _activeWindowTimer = Timer(delay, _publishActiveMessages);
  }

  static String _languageCodeFor(Locale? locale) {
    return locale?.languageCode == 'fr' ? 'fr' : 'en';
  }
}
