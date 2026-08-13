import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_locales.dart';
import '../../../shared/widgets/checkers_background.dart';
import '../../../shared/widgets/checkers_flag_icon.dart';
import '../../../shared/widgets/checkers_gradient_button.dart';
import '../../../shared/widgets/checkers_logo_mark.dart';
import '../../../shared/widgets/checkers_staggered_entrance.dart';
import '../../../translations/translation_keys.dart';
import '../controller/landing_controller.dart';

class LandingView extends GetView<LandingController> {
  const LandingView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: CheckersBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const CheckersLogoMark(),
                    const SizedBox(height: 10),
                    Text(
                      TranslationKeys.landingTagline.tr,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge!.copyWith(
                        color: theme.colorScheme.onPrimary.withValues(
                          alpha: 0.85,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const _LanguageSelector(),
                    const SizedBox(height: 28),
                    Obx(() {
                      final busy = controller.isBusy.value;
                      return CheckersStaggeredEntrance(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CheckersGradientButton(
                            key: const Key('landing-google-button'),
                            label: TranslationKeys.continueWithGoogle.tr,
                            onPressed:
                                busy ? null : controller.signInWithGoogle,
                          ),
                          const SizedBox(height: 14),
                          if (controller.supportsAppleSignIn) ...[
                            CheckersGradientButton(
                              key: const Key('landing-apple-button'),
                              label: TranslationKeys.continueWithApple.tr,
                              onPressed:
                                  busy ? null : controller.signInWithApple,
                            ),
                            const SizedBox(height: 14),
                          ],
                          CheckersGradientButton(
                            key: const Key('landing-guest-button'),
                            label: TranslationKeys.playAsGuest.tr,
                            gradientStyle: CheckersGradientButtonStyle.logo,
                            onPressed: busy ? null : controller.signInAsGuest,
                          ),
                        ],
                      );
                    }),
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

class _LanguageSelector extends GetView<LandingController> {
  const _LanguageSelector();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() {
      final selected = controller.locale.value;
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _LanguageChip(
            key: const Key('landing-language-en'),
            label: TranslationKeys.languageEnglish.tr,
            flag: CheckersFlagKind.english,
            isSelected: selected.languageCode == 'en',
            onTap: () => controller.changeLocale(AppLocales.english),
            theme: theme,
          ),
          const SizedBox(width: 12),
          _LanguageChip(
            key: const Key('landing-language-fr'),
            label: TranslationKeys.languageFrench.tr,
            flag: CheckersFlagKind.french,
            isSelected: selected.languageCode == 'fr',
            onTap: () => controller.changeLocale(AppLocales.french),
            theme: theme,
          ),
        ],
      );
    });
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.label,
    required this.flag,
    required this.isSelected,
    required this.onTap,
    required this.theme,
    super.key,
  });

  final String label;
  final CheckersFlagKind flag;
  final bool isSelected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final brandGold = theme.colorScheme.onPrimary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.shadow.withValues(
            alpha: isSelected ? 0.42 : 0.2,
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: brandGold.withValues(alpha: isSelected ? 1 : 0.4),
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckersFlagIcon(kind: flag),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.bodyLarge!.copyWith(
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
