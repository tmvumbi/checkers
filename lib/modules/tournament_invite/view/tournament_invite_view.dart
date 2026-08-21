import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../shared/widgets/checkers_background.dart';
import '../../../shared/widgets/checkers_gradient_button.dart';
import '../../../shared/widgets/checkers_search_field.dart';
import '../../../shared/widgets/checkers_square_icon_button.dart';
import '../../../themes/app_theme.dart';
import '../../../translations/translation_keys.dart';
import '../controller/tournament_invite_controller.dart';

class TournamentInviteView extends GetView<TournamentInviteController> {
  const TournamentInviteView({super.key});

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
                          TranslationKeys.tournamentInviteTitle.tr,
                          style: theme.textTheme.headlineMedium!.copyWith(
                            color: brand.brandGold,
                            fontSize: 24,
                          ),
                        ),
                      ),
                      CheckersSquareIconButton(
                        key: const Key('tournament-invite-close'),
                        icon: Icons.close,
                        dimension: 44,
                        iconSize: 24,
                        tooltip: TranslationKeys.close.tr,
                        onPressed: Get.back<void>,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CheckersGradientButton(
                    key: const Key('tournament-share-link'),
                    label: TranslationKeys.shareInviteLink.tr,
                    gradientStyle: CheckersGradientButtonStyle.logo,
                    minHeight: 50,
                    onPressed: controller.shareLink,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    TranslationKeys.invitePlayersTitle.tr,
                    style: theme.textTheme.bodyLarge!.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckersSearchField(
                    key: const Key('tournament-invite-search'),
                    hint: TranslationKeys.searchPlayersHint.tr,
                    onChanged: (value) => controller.search.value = value,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Obx(() {
                      if (controller.loading.value) {
                        return Center(
                          child: CircularProgressIndicator(
                            color: brand.brandGold,
                          ),
                        );
                      }
                      final players = controller.players;
                      if (players.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              TranslationKeys.invitePlayersEmpty.tr,
                              key: const Key('tournament-invite-empty'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge!.copyWith(
                                color: theme.colorScheme.onPrimary
                                    .withValues(alpha: 0.7),
                                fontSize: 15,
                              ),
                            ),
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount:
                            players.length +
                            (controller.hasMore.value ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == players.length) {
                            return TextButton(
                              key: const Key('tournament-invite-load-more'),
                              onPressed: controller.loadMore,
                              child: Text(
                                TranslationKeys.loadMore.tr,
                                style: TextStyle(
                                  color: brand.brandGold,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          }
                          final player = players[index];
                          return Obx(() {
                            final isSelected = controller.selected.contains(
                              player.uid,
                            );
                            return InkWell(
                              key: Key(
                                'tournament-invite-player-${player.uid}',
                              ),
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => controller.toggle(player.uid),
                              child: Container(
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
                                    color: isSelected
                                        ? brand.brandGold
                                        : theme.colorScheme.onPrimary
                                              .withValues(alpha: 0.5),
                                    width: isSelected ? 2 : 1,
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
                                          color:
                                              theme.colorScheme.onPrimary,
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
                                              color: theme
                                                  .colorScheme
                                                  .onPrimary
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
                                              color: theme
                                                  .colorScheme
                                                  .onPrimary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                    Text(
                                      '${player.rating}',
                                      style: theme.textTheme.bodyLarge!
                                          .copyWith(
                                            color: brand.brandGold,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(width: 10),
                                    Icon(
                                      isSelected
                                          ? Icons.check_box
                                          : Icons
                                                .check_box_outline_blank,
                                      size: 24,
                                      color: isSelected
                                          ? brand.brandGold
                                          : theme.colorScheme.onPrimary
                                                .withValues(alpha: 0.6),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Obx(
                    () => CheckersGradientButton(
                      key: const Key('tournament-send-invites'),
                      label: TranslationKeys.tournamentSendInvites.trParams({
                        'count': '${controller.selected.length}',
                      }),
                      minHeight: 52,
                      onPressed:
                          controller.selected.isEmpty ||
                              controller.sending.value
                          ? null
                          : controller.sendInvites,
                    ),
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
