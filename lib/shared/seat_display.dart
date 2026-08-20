import 'package:get/get.dart';

import '../data/models/online_game.dart';
import '../translations/translation_keys.dart';

/// Localized difficulty label from a backend level string.
String difficultyLabel(String? levelName) {
  return switch (levelName) {
    'easy' => TranslationKeys.difficultyEasy.tr,
    'medium' => TranslationKeys.difficultyMedium.tr,
    'hard' => TranslationKeys.difficultyHard.tr,
    _ => '',
  };
}

/// Display name for a seat: bots render as "PC (level)".
String seatDisplayName(OnlineGamePlayer? player, {String? aiLevel}) {
  if (player == null) {
    return '…';
  }
  if (player.isBot) {
    final label = difficultyLabel(aiLevel);
    return label.isEmpty ? 'PC' : 'PC ($label)';
  }
  return player.nickname;
}
