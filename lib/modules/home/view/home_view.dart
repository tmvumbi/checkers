import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_locales.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/seat_display.dart';
import '../../../shared/widgets/checkers_background.dart';
import '../../../shared/widgets/checkers_flag_icon.dart';
import '../../../shared/widgets/checkers_gradient_button.dart';
import '../../../shared/widgets/checkers_logo_mark.dart';
import '../../../shared/widgets/checkers_modal.dart';
import '../../../shared/widgets/checkers_staggered_entrance.dart';
import '../../../themes/app_theme.dart';
import '../../../translations/translation_keys.dart';
import '../controller/home_controller.dart';
import 'widgets/play_pc_modal.dart';
import 'widgets/play_people_modal.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CheckersBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 86),
                  child: Obx(() => _HomeTabBody(tab: controller.tab.value)),
                ),
              ),
              const Positioned(
                left: 14,
                right: 14,
                bottom: 8,
                child: _HomeBottomNavigation(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeTabBody extends StatelessWidget {
  const _HomeTabBody({required this.tab});

  final HomeTab tab;

  @override
  Widget build(BuildContext context) {
    return switch (tab) {
      HomeTab.play => const _PlayTab(),
      HomeTab.watch => const _WatchTab(),
      HomeTab.leaderboard => const _LeaderboardTab(),
      HomeTab.more => const _MoreTab(),
    };
  }
}

class _PlayTab extends GetView<HomeController> {
  const _PlayTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HomeProfileHeader(),
              const SizedBox(height: 18),
              const CheckersLogoMark(compact: true),
              const SizedBox(height: 26),
              CheckersStaggeredEntrance(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CheckersGradientButton(
                    key: const Key('home-play-pc-button'),
                    label: TranslationKeys.playWithPc.tr,
                    onPressed: () => _showPlayPcModal(context),
                  ),
                  const SizedBox(height: 14),
                  CheckersGradientButton(
                    key: const Key('home-play-people-button'),
                    label: TranslationKeys.playWithPeople.tr,
                    onPressed: () => _showPlayPeopleModal(context),
                  ),
                  const SizedBox(height: 14),
                  CheckersGradientButton(
                    key: const Key('home-how-to-play-button'),
                    label: TranslationKeys.howToPlay.tr,
                    gradientStyle: CheckersGradientButtonStyle.logo,
                    onPressed: () => Get.toNamed<void>(AppRoutes.howToPlay),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPlayPcModal(BuildContext context) {
    showCheckersModal<void>(
      context: context,
      builder: (dialogContext) => const PlayPcModalContent(),
    );
  }

  void _showPlayPeopleModal(BuildContext context) {
    showCheckersModal<void>(
      context: context,
      builder: (dialogContext) => const PlayPeopleModalContent(),
    );
  }

}

class _HomeProfileHeader extends GetView<HomeController> {
  const _HomeProfileHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandTheme = theme.extension<CheckersThemeExtension>()!;

    return Obx(() {
      final profile = controller.profile.value;
      return Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: theme.colorScheme.onPrimary, width: 2),
              color: theme.colorScheme.shadow.withValues(alpha: 0.35),
              image: profile?.photoUrl == null
                  ? null
                  : DecorationImage(
                      image: NetworkImage(profile!.photoUrl!),
                      fit: BoxFit.cover,
                    ),
            ),
            child: profile?.photoUrl == null
                ? Icon(
                    Icons.person,
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TranslationKeys.welcomeBack.tr,
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
                  ),
                ),
                Text(
                  profile?.nickname ?? '',
                  key: const Key('home-profile-nickname'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineMedium!.copyWith(
                    color: brandTheme.brandGold,
                    fontSize: 24,
                  ),
                ),
              ],
            ),
          ),
          if (profile != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.shadow.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: brandTheme.brandGold.withValues(alpha: 0.8),
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.military_tech, color: brandTheme.brandGold),
                  const SizedBox(width: 4),
                  Text(
                    '${profile.rating}',
                    key: const Key('home-profile-rating'),
                    style: theme.textTheme.bodyLarge!.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }
}

class _WatchTab extends GetView<HomeController> {
  const _WatchTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;

    return Obx(() {
      if (controller.watchLoading.value) {
        return Center(
          child: CircularProgressIndicator(color: brand.brandGold),
        );
      }
      final games = controller.watchableGames;
      if (games.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.visibility_outlined,
                  size: 56,
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 12),
                Text(
                  TranslationKeys.watchEmpty.tr,
                  key: const Key('watch-empty'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: games.length,
        itemBuilder: (context, index) {
          final game = games[index];
          final white = game.players
              .where((p) => p.color?.name == 'white')
              .toList();
          final black = game.players
              .where((p) => p.color?.name == 'black')
              .toList();
          return InkWell(
            key: Key('watch-game-${game.id}'),
            onTap: () => controller.openWatchGame(game),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.shadow.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.6),
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      seatDisplayName(
                        white.isEmpty ? null : white.first,
                        aiLevel: game.aiLevel,
                      ),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge!.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'VS',
                      style: theme.textTheme.bodyLarge!.copyWith(
                        color: brand.brandGold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      seatDisplayName(
                        black.isEmpty ? null : black.first,
                        aiLevel: game.aiLevel,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge!.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }
}

class _LeaderboardTab extends GetView<HomeController> {
  const _LeaderboardTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;

    return Obx(() {
      if (controller.leaderboardLoading.value) {
        return Center(
          child: CircularProgressIndicator(color: brand.brandGold),
        );
      }
      final players = controller.leaderboard;
      if (players.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              TranslationKeys.leaderboardEmpty.tr,
              key: const Key('leaderboard-empty'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge!.copyWith(
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
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
          final isPodium = index < 3;
          final rankColor = switch (index) {
            0 => brand.brandGold,
            1 => const Color(0xFFC0C0C0),
            2 => const Color(0xFFCD7F32),
            _ => theme.colorScheme.onPrimary.withValues(alpha: 0.7),
          };
          return Container(
            key: Key('leaderboard-row-$index'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: isPodium ? 14 : 10,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.shadow.withValues(
                alpha: isPodium ? 0.45 : 0.3,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isPodium
                    ? rankColor
                    : theme.colorScheme.onPrimary.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    '${index + 1}',
                    style: theme.textTheme.headlineMedium!.copyWith(
                      color: rankColor,
                      fontSize: isPodium ? 24 : 18,
                    ),
                  ),
                ),
                if (isPodium) ...[
                  Icon(Icons.emoji_events, color: rankColor, size: 22),
                  const SizedBox(width: 8),
                ],
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isPodium
                          ? rankColor
                          : theme.colorScheme.onPrimary.withValues(alpha: 0.7),
                      width: 2,
                    ),
                    color: theme.colorScheme.shadow.withValues(alpha: 0.4),
                    image: player.photoUrl == null
                        ? null
                        : DecorationImage(
                            image: NetworkImage(player.photoUrl!),
                            fit: BoxFit.cover,
                          ),
                  ),
                  child: player.photoUrl == null
                      ? Icon(
                          Icons.person,
                          size: 20,
                          color: theme.colorScheme.onPrimary
                              .withValues(alpha: 0.7),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        player.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge!.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: isPodium ? 17 : 15,
                        ),
                      ),
                      Text(
                        '${player.wins}W · ${player.losses}L · '
                        '${player.draws}D',
                        style: theme.textTheme.bodyLarge!.copyWith(
                          color: theme.colorScheme.onPrimary.withValues(
                            alpha: 0.6,
                          ),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${player.rating}',
                  style: theme.textTheme.headlineMedium!.copyWith(
                    color: brand.brandGold,
                    fontSize: isPodium ? 22 : 18,
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }
}

class _MoreTab extends GetView<HomeController> {
  const _MoreTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: CheckersStaggeredEntrance(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CheckersGradientButton(
                key: const Key('more-languages-button'),
                label: TranslationKeys.moreLanguages.tr,
                onPressed: () => _showLanguagesModal(context),
              ),
              const SizedBox(height: 14),
              CheckersGradientButton(
                key: const Key('more-edit-profile-button'),
                label: TranslationKeys.moreEditProfile.tr,
                onPressed: controller.openEditProfile,
              ),
              const SizedBox(height: 14),
              CheckersGradientButton(
                key: const Key('more-share-app-button'),
                label: TranslationKeys.moreShareApp.tr,
                onPressed: controller.shareApp,
              ),
              const SizedBox(height: 14),
              CheckersGradientButton(
                key: const Key('more-feedback-button'),
                label: TranslationKeys.moreFeedback.tr,
                onPressed: () => _showFeedbackModal(context),
              ),
              const SizedBox(height: 14),
              CheckersGradientButton(
                key: const Key('more-log-out-button'),
                label: TranslationKeys.moreLogOut.tr,
                gradientStyle: CheckersGradientButtonStyle.logo,
                onPressed: () => _confirmLogOut(context),
              ),
              const SizedBox(height: 14),
              CheckersGradientButton(
                key: const Key('more-delete-account-button'),
                label: TranslationKeys.moreDeleteAccount.tr,
                gradientStyle: CheckersGradientButtonStyle.logo,
                onPressed: () => _confirmDeleteAccount(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFeedbackModal(BuildContext context) {
    final textController = TextEditingController();
    showCheckersModal<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckersModalHeader(
              title: TranslationKeys.feedbackTitle.tr,
              closeKey: const Key('feedback-close'),
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  key: const Key('feedback-text'),
                  controller: textController,
                  maxLines: 5,
                  maxLength: 2000,
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: theme.colorScheme.onPrimary,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                    hintText: TranslationKeys.feedbackHint.tr,
                    hintStyle: theme.textTheme.bodyLarge!.copyWith(
                      color: theme.colorScheme.onPrimary.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            CheckersGradientButton(
              key: const Key('feedback-send'),
              label: TranslationKeys.feedbackSend.tr,
              onPressed: () async {
                final sent =
                    await controller.sendFeedback(textController.text);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                Get.snackbar(
                  '',
                  sent
                      ? TranslationKeys.feedbackThanks.tr
                      : TranslationKeys.feedbackFailed.tr,
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteAccount(BuildContext context) {
    showCheckersModal<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              TranslationKeys.deleteAccountTitle.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium!.copyWith(
                color: theme.extension<CheckersThemeExtension>()!.brandGold,
                fontSize: 24,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              TranslationKeys.deleteAccountMessage.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge!.copyWith(
                color: theme.colorScheme.onPrimary,
                fontSize: 15,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 20),
            CheckersGradientButton(
              key: const Key('delete-account-confirm'),
              label: TranslationKeys.confirm.tr,
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                final deleted = await controller.deleteAccount();
                if (!deleted) {
                  Get.snackbar(
                    '',
                    TranslationKeys.deleteAccountFailed.tr,
                  );
                }
              },
            ),
            const SizedBox(height: 10),
            CheckersGradientButton(
              label: TranslationKeys.cancel.tr,
              gradientStyle: CheckersGradientButtonStyle.logo,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  void _showLanguagesModal(BuildContext context) {
    showCheckersModal<void>(
      context: context,
      builder: (dialogContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckersModalHeader(
              title: TranslationKeys.moreLanguages.tr,
              closeKey: const Key('languages-close'),
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
            const SizedBox(height: 20),
            _LanguageModalRow(
              label: TranslationKeys.languageEnglish.tr,
              flag: CheckersFlagKind.english,
              onTap: () {
                controller.changeLocale(AppLocales.english);
                Navigator.of(dialogContext).pop();
              },
            ),
            const SizedBox(height: 12),
            _LanguageModalRow(
              label: TranslationKeys.languageFrench.tr,
              flag: CheckersFlagKind.french,
              onTap: () {
                controller.changeLocale(AppLocales.french);
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _confirmLogOut(BuildContext context) {
    if (!controller.isAnonymous) {
      controller.logOut();
      return;
    }
    showCheckersModal<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              TranslationKeys.logOutAnonymousWarningTitle.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium!.copyWith(
                color: theme.extension<CheckersThemeExtension>()!.brandGold,
                fontSize: 26,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              TranslationKeys.logOutAnonymousWarningMessage.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge!.copyWith(
                color: theme.colorScheme.onPrimary,
                fontSize: 17,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 22),
            CheckersGradientButton(
              key: const Key('more-log-out-confirm'),
              label: TranslationKeys.confirm.tr,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                controller.logOut();
              },
            ),
            const SizedBox(height: 12),
            CheckersGradientButton(
              label: TranslationKeys.cancel.tr,
              gradientStyle: CheckersGradientButtonStyle.logo,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }
}

class _LanguageModalRow extends StatelessWidget {
  const _LanguageModalRow({
    required this.label,
    required this.flag,
    required this.onTap,
  });

  final String label;
  final CheckersFlagKind flag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.shadow.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.onPrimary, width: 2),
        ),
        child: Row(
          children: [
            CheckersFlagIcon(kind: flag),
            const SizedBox(width: 12),
            Text(
              label,
              style: theme.textTheme.bodyLarge!.copyWith(
                color: theme.colorScheme.onPrimary,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeBottomNavigation extends GetView<HomeController> {
  const _HomeBottomNavigation();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.shadow.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.onPrimary.withValues(alpha: 0.6),
        ),
      ),
      child: Obx(() {
        final selected = controller.tab.value;
        return Row(
          children: [
            _BottomNavigationItem(
              tab: HomeTab.play,
              icon: Icons.play_circle_outline,
              label: TranslationKeys.tabPlay.tr,
              isSelected: selected == HomeTab.play,
            ),
            const _BottomNavigationDivider(),
            _BottomNavigationItem(
              tab: HomeTab.watch,
              icon: Icons.visibility_outlined,
              label: TranslationKeys.tabWatch.tr,
              isSelected: selected == HomeTab.watch,
            ),
            const _BottomNavigationDivider(),
            _BottomNavigationItem(
              tab: HomeTab.leaderboard,
              icon: Icons.emoji_events_outlined,
              label: TranslationKeys.tabTop30.tr,
              isSelected: selected == HomeTab.leaderboard,
            ),
            const _BottomNavigationDivider(),
            _BottomNavigationItem(
              tab: HomeTab.more,
              icon: Icons.more_horiz,
              label: null,
              isSelected: selected == HomeTab.more,
            ),
          ],
        );
      }),
    );
  }
}

class _BottomNavigationItem extends GetView<HomeController> {
  const _BottomNavigationItem({
    required this.tab,
    required this.icon,
    required this.label,
    required this.isSelected,
  });

  final HomeTab tab;
  final IconData icon;
  final String? label;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandTheme = theme.extension<CheckersThemeExtension>()!;
    final color = isSelected
        ? brandTheme.brandGold
        : theme.colorScheme.onPrimary.withValues(alpha: 0.7);

    return Expanded(
      child: InkWell(
        key: Key('home-tab-${tab.name}'),
        onTap: () => controller.selectTab(tab),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 30, color: color),
              if (label != null) ...[
                const SizedBox(height: 2),
                Text(
                  label!,
                  style: theme.textTheme.bodyLarge!.copyWith(
                    fontSize: 15,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavigationDivider extends StatelessWidget {
  const _BottomNavigationDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.4),
    );
  }
}
