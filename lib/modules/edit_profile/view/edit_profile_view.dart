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
                    Text(
                      TranslationKeys.editProfileTitle.tr,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium!.copyWith(
                        color: brandTheme.brandGold,
                      ),
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
                    const SizedBox(height: 24),
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
      final photoUrl = controller.photoUrl.value;
      return Center(
        child: Container(
          width: 108,
          height: 108,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: theme.colorScheme.onPrimary, width: 3),
            color: theme.colorScheme.shadow.withValues(alpha: 0.35),
            image: photoUrl == null
                ? null
                : DecorationImage(
                    image: NetworkImage(photoUrl),
                    fit: BoxFit.cover,
                  ),
          ),
          child: photoUrl == null
              ? Icon(
                  Icons.person,
                  size: 56,
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
                )
              : null,
        ),
      );
    });
  }
}
