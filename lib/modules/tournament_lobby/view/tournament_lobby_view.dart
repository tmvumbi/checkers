import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/tournament_display.dart';
import '../../../shared/widgets/checkers_background.dart';
import '../../../shared/widgets/checkers_gradient_button.dart';
import '../../../shared/widgets/checkers_square_icon_button.dart';
import '../../../themes/app_theme.dart';
import '../../../translations/translation_keys.dart';
import '../controller/tournament_lobby_controller.dart';

class TournamentLobbyView extends GetView<TournamentLobbyController> {
  const TournamentLobbyView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;

    return Scaffold(
      body: CheckersBackground(
        child: SizedBox.expand(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          TranslationKeys.tournamentLobbyTitle.tr,
                          style: theme.textTheme.headlineMedium!.copyWith(
                            color: brand.brandGold,
                            fontSize: 26,
                          ),
                        ),
                      ),
                      CheckersSquareIconButton(
                        key: const Key('lobby-instructions-button'),
                        icon: Icons.info_outline,
                        dimension: 44,
                        iconSize: 24,
                        tooltip: TranslationKeys.tournamentHowTitle.tr,
                        onPressed: () => showTournamentInstructions(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.shadow.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: brand.brandGold.withValues(alpha: 0.8),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          TranslationKeys.tournamentNextStart.tr,
                          style: theme.textTheme.bodyLarge!.copyWith(
                            color: theme.colorScheme.onPrimary.withValues(
                              alpha: 0.8,
                            ),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Obx(
                          () => Text(
                            controller.countdown.value,
                            key: const Key('lobby-countdown'),
                            style: theme.textTheme.headlineMedium!.copyWith(
                              color: brand.brandGold,
                              fontSize: 40,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          TranslationKeys.tournamentMinPlayers.tr,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge!.copyWith(
                            color: theme.colorScheme.onPrimary.withValues(
                              alpha: 0.7,
                            ),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Obx(() {
                    final notice = controller.missedTickNotice.value;
                    if (notice == null) {
                      return const SizedBox(height: 16);
                    }
                    return Container(
                      key: const Key('lobby-missed-tick'),
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.shadow.withValues(
                          alpha: 0.55,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.orangeAccent.withValues(alpha: 0.9),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.hourglass_bottom,
                            size: 18,
                            color: Colors.orangeAccent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              notice,
                              style: theme.textTheme.bodyLarge!.copyWith(
                                color: theme.colorScheme.onPrimary,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  Obx(
                    () => Text(
                      TranslationKeys.tournamentLobbyPlayers.trParams({
                        'count': '${controller.players.length}',
                      }),
                      style: theme.textTheme.bodyLarge!.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Obx(() {
                      if (controller.joining.value) {
                        return Center(
                          child: CircularProgressIndicator(
                            color: brand.brandGold,
                          ),
                        );
                      }
                      final players = controller.players;
                      return ListView.builder(
                        itemCount: players.length,
                        itemBuilder: (context, index) {
                          final player = players[index];
                          return Container(
                            key: Key('lobby-player-${player.uid}'),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.shadow.withValues(
                                alpha: 0.3,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: theme.colorScheme.onPrimary.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.colorScheme.onPrimary,
                                      width: 2,
                                    ),
                                    image: player.photoUrl == null
                                        ? null
                                        : DecorationImage(
                                            image: NetworkImage(
                                              player.photoUrl!,
                                            ),
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                  child: player.photoUrl == null
                                      ? Icon(
                                          Icons.person,
                                          size: 18,
                                          color: theme.colorScheme.onPrimary
                                              .withValues(alpha: 0.7),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    player.nickname,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyLarge!
                                        .copyWith(
                                          color: theme.colorScheme.onPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                                Text(
                                  '${player.rating}',
                                  style: theme.textTheme.bodyLarge!.copyWith(
                                    color: brand.brandGold,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  CheckersGradientButton(
                    key: const Key('lobby-invite-button'),
                    label: TranslationKeys.tournamentInviteTitle.tr,
                    minHeight: 50,
                    onPressed: () =>
                        Get.toNamed<void>(AppRoutes.tournamentInvite),
                  ),
                  const SizedBox(height: 10),
                  CheckersGradientButton(
                    key: const Key('lobby-leave-button'),
                    label: TranslationKeys.lobbyLeave.tr,
                    gradientStyle: CheckersGradientButtonStyle.logo,
                    onPressed: controller.leave,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
