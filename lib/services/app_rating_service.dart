import 'package:rate_my_app/rate_my_app.dart' hide SharedPreferences;
import 'package:shared_preferences/shared_preferences.dart';

/// Rate-the-app reminder (kopo parity): counts home opens and prompts on
/// the 3rd (then 5th after "later"); rating or declining ends the prompts.
abstract class AppRatingService {
  Future<void> recordAppOpen();
  Future<bool> shouldShowAutomaticPrompt();
  Future<void> markRated();
  Future<void> markLater();
  Future<void> markDeclined();
  Future<void> openStore();
}

class RateMyAppRatingService extends AppRatingService {
  static const int firstPromptOpenCount = 3;
  static const int laterPromptOpenCount = 5;

  static const String _openCountKey = 'app_open_count';
  static const String _ratedKey = 'app_rating_rated';
  static const String _declinedKey = 'app_rating_declined';
  static const String _nextPromptKey = 'app_rating_next_prompt_open_count';

  /// Set when the iOS app ships (numeric App Store id).
  static const String? iosAppStoreId = null;

  static bool _recordedOpenThisProcess = false;

  @override
  Future<void> recordAppOpen() async {
    if (_recordedOpenThisProcess) {
      return;
    }
    _recordedOpenThisProcess = true;
    final preferences = await SharedPreferences.getInstance();
    final count = preferences.getInt(_openCountKey) ?? 0;
    await preferences.setInt(_openCountKey, count + 1);
  }

  @override
  Future<bool> shouldShowAutomaticPrompt() async {
    final preferences = await SharedPreferences.getInstance();
    final declined = preferences.getBool(_declinedKey) ?? false;
    final rated = preferences.getBool(_ratedKey) ?? false;
    if (declined || rated) {
      return false;
    }

    final count = preferences.getInt(_openCountKey) ?? 0;
    final nextPromptCount =
        preferences.getInt(_nextPromptKey) ?? firstPromptOpenCount;
    return count >= nextPromptCount;
  }

  @override
  Future<void> markRated() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_ratedKey, true);
  }

  @override
  Future<void> markLater() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_nextPromptKey, laterPromptOpenCount);
  }

  @override
  Future<void> markDeclined() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_declinedKey, true);
  }

  @override
  Future<void> openStore() async {
    final rateMyApp = RateMyApp(
      preferencesPrefix: 'checkers_rate_my_app_',
      minDays: 0,
      minLaunches: 0,
      googlePlayIdentifier: 'club.contribution.checkers',
      appStoreIdentifier: iosAppStoreId,
    );
    await rateMyApp.init();
    await rateMyApp.callEvent(RateMyAppEventType.rateButtonPressed);
    await rateMyApp.launchStore();
  }
}
