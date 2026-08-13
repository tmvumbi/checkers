import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../data/models/user_profile.dart';
import '../../../routes/app_routes.dart';
import '../../../services/analytics_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/profile_service.dart';
import '../../../translations/translation_keys.dart';

class EditProfileController extends GetxController {
  EditProfileController({
    AuthService? authService,
    ProfileService? profileService,
    AnalyticsService? analyticsService,
  }) : _authService = authService ?? Get.find(),
       _profileService = profileService ?? Get.find(),
       _analyticsService = analyticsService ?? Get.find();

  final AuthService _authService;
  final ProfileService _profileService;
  final AnalyticsService _analyticsService;

  final TextEditingController nicknameController = TextEditingController();
  final RxBool isSaving = false.obs;
  final RxnString validationError = RxnString();
  final RxnString photoUrl = RxnString();

  UserProfile? _existingProfile;

  @override
  void onReady() {
    super.onReady();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _authService.currentUser;
    if (user == null) {
      Get.offAllNamed<void>(AppRoutes.landing);
      return;
    }
    final result = await _profileService.getProfile(user.uid);
    result.when(
      success: (profile) {
        _existingProfile = profile;
        if (profile != null) {
          nicknameController.text = profile.nickname;
          photoUrl.value = profile.photoUrl;
        } else if ((user.displayName ?? '').isNotEmpty) {
          nicknameController.text = user.displayName!;
        }
      },
      failure: (_) {},
    );
  }

  Future<void> save() async {
    final user = _authService.currentUser;
    if (user == null) {
      Get.offAllNamed<void>(AppRoutes.landing);
      return;
    }
    final nickname = nicknameController.text.trim();
    if (nickname.isEmpty) {
      validationError.value = TranslationKeys.nicknameRequired.tr;
      return;
    }
    validationError.value = null;
    isSaving.value = true;
    await _analyticsService.logEvent('profile_change_attempt');
    final profile =
        (_existingProfile ??
                UserProfile(
                  uid: user.uid,
                  nickname: nickname,
                  isAnonymous: user.isAnonymous,
                ))
            .copyWith(nickname: nickname, isAnonymous: user.isAnonymous);
    final result = await _profileService.upsertProfile(profile);
    isSaving.value = false;
    result.when(
      success: (_) => Get.offAllNamed<void>(AppRoutes.home),
      failure: (_) {
        Get.snackbar('', TranslationKeys.profileSaveFailed.tr);
      },
    );
  }

  @override
  void onClose() {
    nicknameController.dispose();
    super.onClose();
  }
}
