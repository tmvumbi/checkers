import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../routes/app_routes.dart';
import '../../../../shared/widgets/checkers_gradient_button.dart';
import '../../../../themes/app_theme.dart';
import '../../../../translations/translation_keys.dart';
import '../../../online_lobby/controller/online_lobby_controller.dart';

/// "Play with People": pick a preset, join public matchmaking.
/// (Friend invites arrive with M3.)
class PlayPeopleModalContent extends StatelessWidget {
  const PlayPeopleModalContent({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;

    void join(String preset) {
      Navigator.of(context).pop();
      Get.toNamed<void>(
        AppRoutes.onlineLobby,
        arguments: OnlineLobbyArguments(preset: preset),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          TranslationKeys.playWithPeople.tr,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium!.copyWith(
            color: brand.brandGold,
            fontSize: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          TranslationKeys.rules.tr,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge!.copyWith(
            color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 18),
        CheckersGradientButton(
          key: const Key('play-people-international'),
          label: TranslationKeys.presetInternational.tr,
          minHeight: 54,
          onPressed: () => join('international'),
        ),
        const SizedBox(height: 12),
        CheckersGradientButton(
          key: const Key('play-people-brazilian'),
          label: TranslationKeys.presetBrazilian.tr,
          minHeight: 54,
          onPressed: () => join('brazilian'),
        ),
        const SizedBox(height: 12),
        CheckersGradientButton(
          key: const Key('play-people-american'),
          label: TranslationKeys.presetAmerican.tr,
          minHeight: 54,
          onPressed: () => join('american'),
        ),
      ],
    );
  }
}
