import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_locales.dart';
import '../../../data/models/online_game.dart';
import '../../../data/models/tournament.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/tournament_display.dart';
import '../../../services/block_service.dart';
import '../../../shared/widgets/checkers_ad_banner.dart';
import '../../../shared/seat_display.dart';
import '../../../shared/widgets/checkers_background.dart';
import '../../../shared/widgets/checkers_flag_icon.dart';
import '../../../shared/widgets/checkers_gradient_button.dart';
import '../../../shared/widgets/checkers_logo_mark.dart';
import '../../../shared/widgets/checkers_modal.dart';
import '../../../shared/widgets/checkers_search_field.dart';
import '../../../shared/widgets/checkers_snackbar.dart';
import '../../../shared/widgets/checkers_square_icon_button.dart';
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
              // Positioned so the loose Stack keeps sizing to its bounds.
              const Positioned(
                left: 0,
                top: 0,
                width: 0,
                height: 0,
                child: _RateAppPromptListener(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the automatic rate-app modal once the controller flags it due.
class _RateAppPromptListener extends GetView<HomeController> {
  const _RateAppPromptListener();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.ratingPromptDue.value) {
        controller.ratingPromptDue.value = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            _showRateAppModal(context, controller);
          }
        });
      }
      return const SizedBox.shrink();
    });
  }

  void _showRateAppModal(BuildContext context, HomeController controller) {
    showCheckersModal<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final brandTheme = theme.extension<CheckersThemeExtension>()!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              TranslationKeys.rateAppPromptTitle.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium!.copyWith(
                color: brandTheme.brandGold,
                fontSize: 24,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              TranslationKeys.rateAppPromptMessage.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge!.copyWith(
                color: theme.colorScheme.onPrimary,
                fontSize: 15,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 20),
            CheckersGradientButton(
              key: const Key('rate-app-accept'),
              label: TranslationKeys.rateAppAccept.tr,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                controller.acceptRatingPrompt();
              },
            ),
            const SizedBox(height: 10),
            CheckersGradientButton(
              key: const Key('rate-app-later'),
              label: TranslationKeys.rateAppLater.tr,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                controller.postponeRatingPrompt();
              },
            ),
            const SizedBox(height: 10),
            CheckersGradientButton(
              key: const Key('rate-app-decline'),
              label: TranslationKeys.rateAppDecline.tr,
              gradientStyle: CheckersGradientButtonStyle.logo,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                controller.declineRatingPrompt();
              },
            ),
          ],
        );
      },
    );
  }
}

class _HomeTabBody extends StatelessWidget {
  const _HomeTabBody({required this.tab});

  final HomeTab tab;

  @override
  Widget build(BuildContext context) {
    final body = switch (tab) {
      HomeTab.play => const _PlayTab(),
      HomeTab.watch => const _WatchTab(),
      HomeTab.tournament => const _TournamentTab(),
      HomeTab.leaderboard => const _LeaderboardTab(),
      HomeTab.more => const _MoreTab(),
    };
    if (tab == HomeTab.play) {
      return body;
    }
    return Column(
      children: [
        const CheckersAdBanner(
          key: Key('home-ad-banner'),
          size: CheckersAdBannerSize.compactAdaptive,
        ),
        Expanded(child: body),
      ],
    );
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

  /// Soft-blocked players may watch but not play (server enforces too).
  bool _playBlocked() {
    if (!Get.isRegistered<BlockService>()) {
      return false;
    }
    if (Get.find<BlockService>().status.value.canPlay) {
      return false;
    }
    showCheckersSnackbar(TranslationKeys.blockedCannotPlay.tr);
    return true;
  }

  void _showPlayPcModal(BuildContext context) {
    if (_playBlocked()) {
      return;
    }
    showCheckersModal<void>(
      context: context,
      builder: (dialogContext) => const PlayPcModalContent(),
    );
  }

  void _showPlayPeopleModal(BuildContext context) {
    if (_playBlocked()) {
      return;
    }
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
          if (controller.hasPlayerMessages) ...[
            const SizedBox(width: 10),
            _HomeMessagesButton(
              unreadMessageCount: controller.playerUnreadMessageCount,
            ),
          ],
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

    Widget sectionTitle(String text, Key key) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        key: key,
        style: theme.textTheme.headlineMedium!.copyWith(
          color: brand.brandGold,
          fontSize: 18,
        ),
      ),
    );

    Widget loadMoreButton(Key key, VoidCallback onPressed) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextButton(
        key: key,
        onPressed: onPressed,
        child: Text(
          TranslationKeys.loadMore.tr,
          style: TextStyle(
            color: brand.brandGold,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

    Widget mutedText(String text, Key key) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        key: key,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge!.copyWith(
          color: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
          fontSize: 14,
        ),
      ),
    );

    Widget playersRow(
      OnlineGameSnapshot game, {
      required Key key,
      required VoidCallback onTap,
      required String centerLabel,
      Widget? trailing,
    }) {
      final white = game.players
          .where((p) => p.color?.name == 'white')
          .toList();
      final black = game.players
          .where((p) => p.color?.name == 'black')
          .toList();
      return InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              _SeatAvatar(
                player: white.isEmpty ? null : white.first,
                theme: theme,
              ),
              const SizedBox(width: 8),
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
                  centerLabel,
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
              const SizedBox(width: 8),
              _SeatAvatar(
                player: black.isEmpty ? null : black.first,
                theme: theme,
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
            ],
          ),
        ),
      );
    }

    Widget liveRow(OnlineGameSnapshot game) => playersRow(
      game,
      key: Key('watch-game-${game.id}'),
      onTap: () => controller.openWatchGame(game),
      centerLabel: 'VS',
    );

    Widget recentRow(OnlineGameSnapshot game) => playersRow(
      game,
      key: Key('recent-game-${game.id}'),
      onTap: () => controller.openRecentGame(game),
      centerLabel: switch (game.result) {
        'whiteWin' => '1 - 0',
        'blackWin' => '0 - 1',
        'draw' => '\u00bd - \u00bd',
        _ => 'VS',
      },
      trailing: Icon(
        Icons.play_circle_outline,
        size: 22,
        color: brand.brandGold.withValues(alpha: 0.9),
      ),
    );

    return Obx(() {
      if (controller.watchLoading.value &&
          controller.watchableGames.isEmpty &&
          controller.recentGames.isEmpty) {
        return Center(child: CircularProgressIndicator(color: brand.brandGold));
      }
      final games = controller.watchableGames;
      final recent = controller.recentGames;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          sectionTitle(
            TranslationKeys.watchLiveSection.tr,
            const Key('watch-live-section'),
          ),
          if (games.isEmpty)
            mutedText(TranslationKeys.watchEmpty.tr, const Key('watch-empty'))
          else
            CheckersStaggeredEntrance(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              itemDelay: const Duration(milliseconds: 60),
              children: [for (final game in games) liveRow(game)],
            ),
          if (controller.hasMoreWatchable.value)
            loadMoreButton(
              const Key('watch-load-more'),
              controller.loadMoreWatchableGames,
            ),
          const SizedBox(height: 12),
          sectionTitle(
            TranslationKeys.watchRecentSection.tr,
            const Key('watch-recent-section'),
          ),
          Row(
            children: [
              Expanded(
                child: CheckersSearchField(
                  hint: TranslationKeys.watchRecentSearchHint.tr,
                  onChanged: (value) => controller.recentSearch.value = value,
                ),
              ),
              const SizedBox(width: 10),
              FilterChip(
                key: const Key('recent-mine-filter'),
                selected: controller.recentMineOnly.value,
                onSelected: (_) => controller.toggleRecentMineOnly(),
                label: Text(TranslationKeys.watchRecentMine.tr),
                labelStyle: TextStyle(
                  color: controller.recentMineOnly.value
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                selectedColor: brand.brandGold,
                checkmarkColor: theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.shadow.withValues(
                  alpha: 0.3,
                ),
                side: BorderSide(
                  color: controller.recentMineOnly.value
                      ? brand.brandGold
                      : theme.colorScheme.onPrimary.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (controller.recentLoading.value)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CircularProgressIndicator(color: brand.brandGold),
              ),
            )
          else if (recent.isEmpty)
            mutedText(
              TranslationKeys.watchRecentEmpty.tr,
              const Key('watch-recent-empty'),
            )
          else
            ...[for (final game in recent) recentRow(game)],
          if (controller.hasMoreRecent.value && !controller.recentLoading.value)
            loadMoreButton(
              const Key('recent-load-more'),
              controller.loadMoreRecentGames,
            ),
        ],
      );
    });
  }
}

class _TournamentTab extends GetView<HomeController> {
  const _TournamentTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: CheckersGradientButton(
                  key: const Key('tournament-join-button'),
                  label: TranslationKeys.joinTournament.tr,
                  minHeight: 52,
                  onPressed: () {
                    if (_playBlockedForTournament()) {
                      return;
                    }
                    controller.openTournamentLobby();
                  },
                ),
              ),
              const SizedBox(width: 10),
              CheckersSquareIconButton(
                key: const Key('tournament-instructions-button'),
                icon: Icons.info_outline,
                dimension: 52,
                iconSize: 28,
                tooltip: TranslationKeys.tournamentHowTitle.tr,
                onPressed: () => showTournamentInstructions(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: Obx(() {
            if (controller.tournamentsLoading.value) {
              return Center(
                child: CircularProgressIndicator(color: brand.brandGold),
              );
            }
            final tournaments = controller.tournaments;
            if (tournaments.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.account_tree_outlined,
                        size: 56,
                        color: theme.colorScheme.onPrimary.withValues(
                          alpha: 0.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        TranslationKeys.tournamentsEmpty.tr,
                        key: const Key('tournaments-empty'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge!.copyWith(
                          color: theme.colorScheme.onPrimary.withValues(
                            alpha: 0.7,
                          ),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                CheckersStaggeredEntrance(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  itemDelay: const Duration(milliseconds: 60),
                  children: [
                    for (final tournament in tournaments)
                      _TournamentRow(tournament: tournament, theme: theme),
                  ],
                ),
                if (controller.hasMoreTournaments.value)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TextButton(
                      key: const Key('tournaments-load-more'),
                      onPressed: controller.loadMoreTournaments,
                      child: Text(
                        TranslationKeys.loadMore.tr,
                        style: TextStyle(
                          color: brand.brandGold,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),
      ],
    );
  }

  bool _playBlockedForTournament() {
    if (!Get.isRegistered<BlockService>()) {
      return false;
    }
    if (Get.find<BlockService>().status.value.canPlay) {
      return false;
    }
    showCheckersSnackbar(TranslationKeys.blockedCannotPlay.tr);
    return true;
  }
}

class _TournamentRow extends GetView<HomeController> {
  const _TournamentRow({required this.tournament, required this.theme});

  final TournamentSummary tournament;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final brand = theme.extension<CheckersThemeExtension>()!;
    return InkWell(
      key: Key('tournament-row-${tournament.id}'),
      onTap: () => controller.openTournament(tournament),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TranslationKeys.tournamentNumber.trParams({
                      'number': '${tournament.number}',
                    }),
                    style: theme.textTheme.bodyLarge!.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    TranslationKeys.tournamentPlayersCount.trParams({
                      'count': '${tournament.participantCount}',
                    }),
                    style: theme.textTheme.bodyLarge!.copyWith(
                      color: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (tournament.isFinished)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emoji_events, size: 20, color: brand.brandGold),
                  const SizedBox(width: 6),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: brand.brandGold.withValues(alpha: 0.9),
                        width: 2,
                      ),
                      color: theme.colorScheme.shadow.withValues(alpha: 0.4),
                      image: tournament.winnerPhotoUrl == null
                          ? null
                          : DecorationImage(
                              image: NetworkImage(tournament.winnerPhotoUrl!),
                              fit: BoxFit.cover,
                            ),
                    ),
                    child: tournament.winnerPhotoUrl == null
                        ? Icon(
                            Icons.person,
                            size: 16,
                            color: theme.colorScheme.onPrimary.withValues(
                              alpha: 0.7,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(
                      tournament.winnerNickname ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge!.copyWith(
                        color: brand.brandGold,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: brand.brandGold, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.redAccent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tournamentStageLabel(tournament.stage),
                      style: theme.textTheme.bodyLarge!.copyWith(
                        color: brand.brandGold,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
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
        return Center(child: CircularProgressIndicator(color: brand.brandGold));
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
      Widget playerRow(int index) {
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
                        color: theme.colorScheme.onPrimary.withValues(
                          alpha: 0.7,
                        ),
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
      }

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CheckersStaggeredEntrance(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            itemDelay: const Duration(milliseconds: 60),
            children: [for (var i = 0; i < players.length; i++) playerRow(i)],
          ),
        ],
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
              // GDPR-only: consent form re-entry, required by AdMob policy.
              Builder(
                builder: (_) {
                  final adService = controller.adServiceOrNull;
                  if (adService == null) {
                    return const SizedBox.shrink();
                  }
                  return Obx(() {
                    if (!adService.isPrivacyOptionsRequired.value) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: CheckersGradientButton(
                        key: const Key('more-privacy-options-button'),
                        label: TranslationKeys.morePrivacyOptions.tr,
                        onPressed: adService.showPrivacyOptions,
                      ),
                    );
                  });
                },
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
                      color: theme.colorScheme.onPrimary.withValues(alpha: 0.5),
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
                final sent = await controller.sendFeedback(textController.text);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                showCheckersSnackbar(
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
                  showCheckersSnackbar(TranslationKeys.deleteAccountFailed.tr);
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
              tab: HomeTab.tournament,
              icon: Icons.account_tree_outlined,
              label: TranslationKeys.tabTournament.tr,
              isSelected: selected == HomeTab.tournament,
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
              Icon(icon, size: 28, color: color),
              if (label != null) ...[
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label!,
                    maxLines: 1,
                    style: theme.textTheme.bodyLarge!.copyWith(
                      fontSize: 13,
                      color: color,
                    ),
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

class _HomeMessagesButton extends StatelessWidget {
  const _HomeMessagesButton({required this.unreadMessageCount});

  final int unreadMessageCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandTheme = theme.extension<CheckersThemeExtension>()!;
    final label = unreadMessageCount > 99 ? '99+' : '$unreadMessageCount';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CheckersSquareIconButton(
          key: const Key('home-messages-button'),
          icon: Icons.mail_outline,
          dimension: 48,
          iconSize: 28,
          onPressed: () => Get.toNamed<void>(AppRoutes.messages),
          tooltip: TranslationKeys.messages.tr,
        ),
        if (unreadMessageCount > 0)
          Positioned(
            right: -5,
            top: -5,
            child: Container(
              key: const Key('home-messages-badge'),
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: brandTheme.brandGold,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: theme.colorScheme.onPrimary,
                  width: 1.5,
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge!.copyWith(
                  color: theme.colorScheme.shadow,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SeatAvatar extends StatelessWidget {
  const _SeatAvatar({required this.player, required this.theme});

  final OnlineGamePlayer? player;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final photoUrl = player?.photoUrl;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
          width: 2,
        ),
        color: theme.colorScheme.shadow.withValues(alpha: 0.4),
        image: photoUrl == null
            ? null
            : DecorationImage(image: NetworkImage(photoUrl), fit: BoxFit.cover),
      ),
      child: photoUrl == null
          ? Icon(
              (player?.isBot ?? false) ? Icons.smart_toy : Icons.person,
              size: 18,
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
            )
          : null,
    );
  }
}
