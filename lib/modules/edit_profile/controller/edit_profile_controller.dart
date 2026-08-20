import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../data/models/user_profile.dart';
import '../../../routes/app_routes.dart';
import '../../../services/analytics_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/profile_photo_service.dart';
import '../../../services/profile_service.dart';
import '../../../translations/translation_keys.dart';

class EditProfileController extends GetxController {
  EditProfileController({
    AuthService? authService,
    ProfileService? profileService,
    ProfilePhotoService? photoService,
    AnalyticsService? analyticsService,
  }) : _authService = authService ?? Get.find(),
       _profileService = profileService ?? Get.find(),
       _photoServiceOverride = photoService,
       _analyticsService = analyticsService ?? Get.find();

  final AuthService _authService;
  final ProfileService _profileService;
  final ProfilePhotoService? _photoServiceOverride;
  final AnalyticsService _analyticsService;

  ProfilePhotoService get _photoService =>
      _photoServiceOverride ?? Get.find();

  final TextEditingController nicknameController = TextEditingController();
  final RxBool isSaving = false.obs;
  final RxnString validationError = RxnString();
  final RxnString photoUrl = RxnString();

  /// Locally picked image awaiting upload; nothing touches the backend
  /// until Save, so closing the page discards it.
  final RxnString pendingPhotoPath = RxnString();
  final RxBool removePhotoRequested = false.obs;

  UserProfile? _existingProfile;

  bool get hasVisiblePhoto =>
      pendingPhotoPath.value != null ||
      (photoUrl.value != null && !removePhotoRequested.value);

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

  Future<void> pickPhoto() async {
    final result = await _photoService.pickImage();
    result.when(
      success: (path) {
        if (path != null) {
          pendingPhotoPath.value = path;
          removePhotoRequested.value = false;
        }
      },
      failure: (_) {},
    );
  }

  void removePhoto() {
    pendingPhotoPath.value = null;
    removePhotoRequested.value = true;
  }

  void close() {
    Get.back<void>();
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

    // Apply photo changes only now, so backing out never mutates anything.
    String? newPhotoUrl;
    var clearPhoto = false;
    final pendingPath = pendingPhotoPath.value;
    if (pendingPath != null) {
      final upload = await _photoService.uploadAvatar(user.uid, pendingPath);
      final uploadFailed = upload.when(
        success: (url) {
          newPhotoUrl = url;
          return false;
        },
        failure: (_) => true,
      );
      if (uploadFailed) {
        isSaving.value = false;
        Get.snackbar('', TranslationKeys.profileSaveFailed.tr);
        return;
      }
    } else if (removePhotoRequested.value) {
      clearPhoto = true;
      await _photoService.deleteAvatar(user.uid);
    }

    final profile =
        (_existingProfile ??
                UserProfile(
                  uid: user.uid,
                  nickname: nickname,
                  isAnonymous: user.isAnonymous,
                ))
            .copyWith(
              nickname: nickname,
              isAnonymous: user.isAnonymous,
              photoUrl: newPhotoUrl,
              clearPhoto: clearPhoto,
            );
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
