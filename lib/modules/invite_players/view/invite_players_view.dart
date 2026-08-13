import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../shared/widgets/checkers_background.dart';
import '../../../shared/widgets/checkers_gradient_button.dart';
import '../../../themes/app_theme.dart';
import '../../../translations/translation_keys.dart';
import '../controller/invite_players_controller.dart';

class InvitePlayersView extends GetView<InvitePlayersController> {
  const InvitePlayersView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;

    return Scaffold(
      body: CheckersBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('invite-players-back'),
                      onPressed: Get.back<void>,
                      icon: Icon(
                        Icons.arrow_back,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        TranslationKeys.invitePlayersTitle.tr,
                        style: theme.textTheme.headlineMedium!.copyWith(
                          color: brand.brandGold,
                          fontSize: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: CheckersGradientButton(
                  key: const Key('invite-share-link'),
                  label: TranslationKeys.shareInviteLink.tr,
                  minHeight: 52,
                  gradientStyle: CheckersGradientButtonStyle.logo,
                  onPressed: controller.shareLink,
                ),
              ),
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
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          TranslationKeys.invitePlayersEmpty.tr,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge!.copyWith(
                            color: theme.colorScheme.onPrimary.withValues(
                              alpha: 0.7,
                            ),
                            fontSize: 16,
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: players.length,
                    itemBuilder: (context, index) {
                      final player = players[index];
                      final inviting =
                          controller.invitingUid.value == player.uid;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.shadow.withValues(
                            alpha: 0.3,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: theme.colorScheme.onPrimary.withValues(
                              alpha: 0.6,
                            ),
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.colorScheme.onPrimary,
                                  width: 2,
                                ),
                                image: player.photoUrl == null
                                    ? null
                                    : DecorationImage(
                                        image:
                                            NetworkImage(player.photoUrl!),
                                        fit: BoxFit.cover,
                                      ),
                              ),
                              child: player.photoUrl == null
                                  ? Icon(
                                      Icons.person,
                                      size: 24,
                                      color: theme.colorScheme.onPrimary
                                          .withValues(alpha: 0.7),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    player.nickname,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyLarge!
                                        .copyWith(
                                          color:
                                              theme.colorScheme.onPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  Text(
                                    '${player.rating}',
                                    style: theme.textTheme.bodyLarge!
                                        .copyWith(
                                          color: brand.brandGold,
                                          fontSize: 13,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              key: Key('invite-player-${player.uid}'),
                              onPressed: inviting
                                  ? null
                                  : () => controller.invite(player),
                              child: Text(
                                TranslationKeys.invite.tr,
                                style: TextStyle(
                                  color: brand.brandGold,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
