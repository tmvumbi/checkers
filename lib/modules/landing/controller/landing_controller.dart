import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_locales.dart';
import '../../../core/network/api_result.dart';
import '../../../routes/app_routes.dart';
import '../../../services/analytics_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/profile_service.dart';
import '../../../translations/translation_keys.dart';

class LandingController extends GetxController {
  LandingController({
    AuthService? authService,
    ProfileService? profileService,
    AnalyticsService? analyticsService,
  }) : _authService = authService ?? Get.find(),
       _profileService = profileService ?? Get.find(),
       _analyticsService = analyticsService ?? Get.find();

  final AuthService _authService;
  final ProfileService _profileService;
  final AnalyticsService _analyticsService;

  final RxBool isBusy = false.obs;
  final Rx<Locale> locale = AppLocales.english.obs;

  bool get supportsAppleSignIn => _authService.supportsAppleSignIn;

  @override
  void onReady() {
    super.onReady();
    _continueExistingSession();
  }

  void _continueExistingSession() {
    final user = _authService.currentUser;
    if (user != null) {
      Get.offAllNamed<void>(AppRoutes.home);
    }
  }

  void changeLocale(Locale newLocale) {
    locale.value = newLocale;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.updateLocale(newLocale);
    });
    _analyticsService.logEvent('language_change_attempt', {
      'language': newLocale.languageCode,
    });
  }

  Future<void> signInAsGuest() => _signIn('guest', _authService.signInAnonymously);

  Future<void> signInWithGoogle() =>
      _signIn('google', _authService.signInWithGoogle);

  Future<void> signInWithApple() =>
      _signIn('apple', _authService.signInWithApple);

  Future<void> _signIn(
    String method,
    Future<ApiResult<AuthUser>> Function() action,
  ) async {
    if (isBusy.value) {
      return;
    }
    isBusy.value = true;
    await _analyticsService.logEvent('login_attempt', {'method': method});
    final result = await action();
    isBusy.value = false;
    result.when(
      success: (user) async {
        final profileResult = await _profileService.getProfile(user.uid);
        final hasNickname = profileResult.when(
          success: (profile) => (profile?.nickname ?? '').isNotEmpty,
          failure: (_) => false,
        );
        if (hasNickname) {
          Get.offAllNamed<void>(AppRoutes.home);
        } else {
          Get.offAllNamed<void>(AppRoutes.editProfile);
        }
      },
      failure: (error) {
        if (error.code.endsWith('cancelled')) {
          return;
        }
        Get.snackbar('', TranslationKeys.signInFailed.tr);
      },
    );
  }
}
