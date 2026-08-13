import 'package:flutter/widgets.dart';

abstract final class AppLocales {
  static const Locale english = Locale('en', 'US');
  static const Locale french = Locale('fr', 'FR');
  static const List<Locale> supported = [english, french];

  static Locale supportedLocaleFor(Locale? locale) {
    if (locale == null) {
      return english;
    }

    return supported.firstWhere(
      (supportedLocale) => supportedLocale.languageCode == locale.languageCode,
      orElse: () => english,
    );
  }
}
