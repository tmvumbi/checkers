import 'package:checkers/services/app_rating_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RateMyAppRatingService service;

  setUp(() {
    service = RateMyAppRatingService();
  });

  test('prompts on the 3rd open, then the 5th after "later"', () async {
    SharedPreferences.setMockInitialValues({'app_open_count': 2});
    await service.recordAppOpen(); // 3rd open (once per process).
    expect(await service.shouldShowAutomaticPrompt(), isTrue);

    await service.markLater();
    expect(await service.shouldShowAutomaticPrompt(), isFalse);

    SharedPreferences.setMockInitialValues({
      'app_open_count': 5,
      'app_rating_next_prompt_open_count': 5,
    });
    expect(await service.shouldShowAutomaticPrompt(), isTrue);
  });

  test('rating or declining silences the prompt forever', () async {
    SharedPreferences.setMockInitialValues({'app_open_count': 99});
    await service.markRated();
    expect(await service.shouldShowAutomaticPrompt(), isFalse);

    SharedPreferences.setMockInitialValues({'app_open_count': 99});
    await service.markDeclined();
    expect(await service.shouldShowAutomaticPrompt(), isFalse);
  });
}
