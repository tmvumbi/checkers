import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import 'constants/app_locales.dart';

/// Persists the chosen language across app restarts.
abstract final class LocalePreference {
  static const String _key = 'preferred_language_code';

  static Future<Locale?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_key);
      if (code == null) {
        return null;
      }
      return AppLocales.supportedLocaleFor(Locale(code));
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(Locale locale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, locale.languageCode);
    } catch (_) {
      // Preference persistence is best-effort.
    }
  }
}
