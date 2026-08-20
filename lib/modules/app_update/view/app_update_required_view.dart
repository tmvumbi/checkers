import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/checkers_background.dart';
import '../../../shared/widgets/checkers_gradient_button.dart';
import '../../../shared/widgets/checkers_logo_mark.dart';
import '../../../themes/app_theme.dart';
import '../../../translations/translation_keys.dart';

class AppUpdateRequiredView extends StatelessWidget {
  const AppUpdateRequiredView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;
    final storeUrl = Get.arguments as String?;

    return Scaffold(
      body: CheckersBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CheckersLogoMark(compact: true),
                  const SizedBox(height: 28),
                  Text(
                    TranslationKeys.updateRequiredTitle.tr,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium!.copyWith(
                      color: brand.brandGold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    TranslationKeys.updateRequiredMessage.tr,
                    key: const Key('update-required-message'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge!.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                  if (storeUrl != null && storeUrl.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    CheckersGradientButton(
                      key: const Key('update-now-button'),
                      label: TranslationKeys.updateNow.tr,
                      onPressed: () => launchUrl(
                        Uri.parse(storeUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
