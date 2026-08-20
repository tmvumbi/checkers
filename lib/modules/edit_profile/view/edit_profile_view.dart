import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../shared/widgets/checkers_background.dart';
import '../../../shared/widgets/checkers_gradient_button.dart';
import '../../../shared/widgets/checkers_staggered_entrance.dart';
import '../../../themes/app_theme.dart';
import '../../../translations/translation_keys.dart';
import '../controller/edit_profile_controller.dart';

class EditProfileView extends GetView<EditProfileController> {
  const EditProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandTheme = theme.extension<CheckersThemeExtension>()!;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: CheckersBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: CheckersStaggeredEntrance(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          TranslationKeys.editProfileTitle.tr,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium!.copyWith(
                            color: brandTheme.brandGold,
                          ),
                        ),
                        if (Navigator.of(context).canPop())
                          Positioned(
                            right: -8,
                            child: IconButton(
                              key: const Key('edit-profile-close'),
                              onPressed: controller.close,
                              icon: Icon(
                                Icons.close,
                                color: theme.colorScheme.onPrimary,
                              ),
                              tooltip: TranslationKeys.close.tr,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      TranslationKeys.privacyNudge.tr,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge!.copyWith(
                        color: theme.colorScheme.onPrimary.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _AvatarPreview(theme: theme),
                    const SizedBox(height: 10),
                    Obx(() {
                      return Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TextButton.icon(
                            key: const Key('edit-profile-change-photo'),
                            onPressed: controller.pickPhoto,
                            icon: Icon(
                              Icons.photo_library_outlined,
                              size: 18,
                              color: brandTheme.brandGold,
                            ),
                            label: Text(
                              TranslationKeys.changePhoto.tr,
                              style: TextStyle(
                                color: brandTheme.brandGold,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (controller.hasVisiblePhoto)
                            TextButton.icon(
                              key: const Key('edit-profile-remove-photo'),
                              onPressed: controller.removePhoto,
                              icon: Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: theme.colorScheme.onPrimary
                                    .withValues(alpha: 0.8),
                              ),
                              label: Text(
                                TranslationKeys.removePhoto.tr,
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimary
                                      .withValues(alpha: 0.8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      );
                    }),
                    const SizedBox(height: 14),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.shadow.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.colorScheme.onPrimary,
                          width: 2,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          key: const Key('edit-profile-nickname'),
                          controller: controller.nicknameController,
                          maxLength: 20,
                          style: theme.textTheme.bodyLarge!.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontSize: 20,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            counterText: '',
                            hintText: TranslationKeys.nicknameLabel.tr,
                            hintStyle: theme.textTheme.bodyLarge!.copyWith(
                              color: theme.colorScheme.onPrimary.withValues(
                                alpha: 0.5,
                              ),
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Obx(() {
                      final error = controller.validationError.value;
                      if (error == null) {
                        return const SizedBox(height: 20);
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          error,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge!.copyWith(
                            color: theme.colorScheme.errorContainer,
                          ),
                        ),
                      );
                    }),
                    Obx(
                      () => CheckersGradientButton(
                        key: const Key('edit-profile-save'),
                        label: TranslationKeys.saveProfile.tr,
                        onPressed:
                            controller.isSaving.value ? null : controller.save,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarPreview extends GetView<EditProfileController> {
  const _AvatarPreview({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final pendingPath = controller.pendingPhotoPath.value;
      final photoUrl = controller.photoUrl.value;
      final removed = controller.removePhotoRequested.value;
      final ImageProvider? image = pendingPath != null
          ? FileImage(File(pendingPath))
          : (photoUrl != null && !removed ? NetworkImage(photoUrl) : null);
      return Center(
        child: InkWell(
          key: const Key('edit-profile-avatar'),
          onTap: controller.pickPhoto,
          customBorder: const CircleBorder(),
          child: Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: theme.colorScheme.onPrimary, width: 3),
              color: theme.colorScheme.shadow.withValues(alpha: 0.35),
              image: image == null
                  ? null
                  : DecorationImage(image: image, fit: BoxFit.cover),
            ),
            child: image == null
                ? Icon(
                    Icons.add_a_photo_outlined,
                    size: 44,
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
                  )
                : null,
          ),
        ),
      );
    });
  }
}
