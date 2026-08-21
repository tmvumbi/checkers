import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../../core/constants/app_locales.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/locale_preference.dart';
import '../../../core/update_gate.dart';
import '../../../core/network/api_result.dart';
import '../../../routes/app_routes.dart';
import '../../../data/models/block_status.dart';
import '../../../services/analytics_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/block_service.dart';
import '../../../services/profile_service.dart';
import '../../../shared/widgets/checkers_snackbar.dart';
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
  late final Rx<Locale> locale =
      AppLocales.supportedLocaleFor(Get.locale).obs;

  bool get supportsAppleSignIn => _authService.supportsAppleSignIn;

  @override
  void onReady() {
    super.onReady();
    _checkVersionThenContinue();
  }

  Future<void> _checkVersionThenContinue() async {
    final gate = await _evaluateUpdateGate();
    if (gate.updateRequired) {
      Get.offAllNamed<void>(
        AppRoutes.appUpdateRequired,
        arguments: gate.storeUrl,
      );
      return;
    }
    final user = _authService.currentUser;
    if (user != null) {
      if (await _isFullyBlocked()) {
        return;
      }
      Get.offAllNamed<void>(AppRoutes.home);
    }
  }

  /// Syncs device identifiers + block status; routes to the blocked wall
  /// and returns true when the player is fully blocked.
  Future<bool> _isFullyBlocked() async {
    if (!Get.isRegistered<BlockService>()) {
      return false;
    }
    final status = await Get.find<BlockService>().sync();
    if (status.level != BlockLevel.full) {
      return false;
    }
    Get.offAllNamed<void>(AppRoutes.blocked, arguments: status);
    return true;
  }

  Future<UpdateGate> _evaluateUpdateGate() async {
    try {
      final row = await Supabase.instance.client
          .from('app_config')
          .select('config')
          .eq('id', 'public')
          .maybeSingle();
      final config =
          (row?['config'] as Map?)?.cast<String, dynamic>() ?? const {};
      return UpdateGate.evaluate(
        config,
        isIOS: !kIsWeb && Platform.isIOS,
        currentVersion: AppStrings.currentAppVersion,
      );
    } catch (_) {
      // Never block play on a config fetch failure.
      return const UpdateGate(updateRequired: false);
    }
  }

  void changeLocale(Locale newLocale) {
    locale.value = newLocale;
    LocalePreference.save(newLocale);
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
        if (await _isFullyBlocked()) {
          return;
        }
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
        // The user-facing message stays generic; the cause goes to the
        // device log, where sign-in problems are actually diagnosable.
        if (kDebugMode) {
          debugPrint('sign-in failed [$method] ${error.code}: ${error.message}');
        }
        showCheckersSnackbar(TranslationKeys.signInFailed.tr);
      },
    );
  }
}
