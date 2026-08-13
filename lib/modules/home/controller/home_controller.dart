import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_locales.dart';
import '../../../data/models/user_profile.dart';
import '../../../routes/app_routes.dart';
import '../../../services/analytics_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/profile_service.dart';

enum HomeTab { play, watch, leaderboard, more }

class HomeController extends GetxController {
  HomeController({
    AuthService? authService,
    ProfileService? profileService,
    AnalyticsService? analyticsService,
  }) : _authService = authService ?? Get.find(),
       _profileService = profileService ?? Get.find(),
       _analyticsService = analyticsService ?? Get.find();

  final AuthService _authService;
  final ProfileService _profileService;
  final AnalyticsService _analyticsService;

  final Rx<HomeTab> tab = HomeTab.play.obs;
  final Rxn<UserProfile> profile = Rxn<UserProfile>();

  bool get isAnonymous => _authService.currentUser?.isAnonymous ?? true;

  @override
  void onReady() {
    super.onReady();
    refreshProfile();
  }

  Future<void> refreshProfile() async {
    final user = _authService.currentUser;
    if (user == null) {
      Get.offAllNamed<void>(AppRoutes.landing);
      return;
    }
    final result = await _profileService.getProfile(user.uid);
    result.when(
      success: (loaded) => profile.value = loaded,
      failure: (_) {},
    );
  }

  void selectTab(HomeTab newTab) {
    if (tab.value == newTab) {
      return;
    }
    tab.value = newTab;
    _analyticsService.logEvent('home_tab_selected', {'tab': newTab.name});
  }

  void changeLocale(Locale locale) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.updateLocale(locale);
    });
  }

  Locale localeFor(String languageCode) {
    return languageCode == 'fr' ? AppLocales.french : AppLocales.english;
  }

  Future<void> openEditProfile() async {
    await Get.toNamed<void>(AppRoutes.editProfile);
    await refreshProfile();
  }

  Future<void> logOut() async {
    await _analyticsService.logEvent('logout_attempt');
    await _authService.signOut();
    Get.offAllNamed<void>(AppRoutes.landing);
  }
}
