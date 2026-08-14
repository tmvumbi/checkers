import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../routes/app_routes.dart';
import '../../../../shared/widgets/checkers_gradient_button.dart';
import '../../../../themes/app_theme.dart';
import '../../../../translations/translation_keys.dart';
import '../../../invite_players/controller/invite_players_controller.dart';
import '../../../online_lobby/controller/online_lobby_controller.dart';

/// "Play with People": pick a preset, then join public matchmaking or
/// invite friends (kopo's two-section modal).
class PlayPeopleModalContent extends StatefulWidget {
  const PlayPeopleModalContent({super.key});

  @override
  State<PlayPeopleModalContent> createState() => _PlayPeopleModalContentState();
}

class _PlayPeopleModalContentState extends State<PlayPeopleModalContent> {
  String _preset = 'international';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;

    void joinMatchmaking() {
      Navigator.of(context).pop();
      Get.toNamed<void>(
        AppRoutes.onlineLobby,
        arguments: OnlineLobbyArguments(preset: _preset),
      );
    }

    void inviteFriends() {
      Navigator.of(context).pop();
      Get.toNamed<void>(
        AppRoutes.invitePlayers,
        arguments: InvitePlayersArguments(preset: _preset),
      );
    }

    Widget presetChip(String preset, String label, Key key) {
      final selected = _preset == preset;
      return InkWell(
        key: key,
        onTap: () => setState(() => _preset = preset),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? brand.brandGold
                  : theme.colorScheme.onPrimary.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge!.copyWith(
              color:
                  selected ? brand.brandGold : theme.colorScheme.onPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Text(
              TranslationKeys.playWithPeople.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium!.copyWith(
                color: brand.brandGold,
                fontSize: 24,
              ),
            ),
            Positioned(
              right: -8,
              child: IconButton(
                key: const Key('play-people-close'),
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close, color: theme.colorScheme.onPrimary),
                tooltip: TranslationKeys.close.tr,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        presetChip(
          'international',
          TranslationKeys.presetInternational.tr,
          const Key('play-people-international'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: presetChip(
                'brazilian',
                TranslationKeys.presetBrazilian.tr,
                const Key('play-people-brazilian'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: presetChip(
                'american',
                TranslationKeys.presetAmerican.tr,
                const Key('play-people-american'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        CheckersGradientButton(
          key: const Key('play-people-join'),
          label: TranslationKeys.joinOnlineGame.tr,
          minHeight: 54,
          onPressed: joinMatchmaking,
        ),
        const SizedBox(height: 12),
        CheckersGradientButton(
          key: const Key('play-people-invite'),
          label: TranslationKeys.inviteFriends.tr,
          minHeight: 54,
          gradientStyle: CheckersGradientButtonStyle.logo,
          onPressed: inviteFriends,
        ),
      ],
    );
  }
}
