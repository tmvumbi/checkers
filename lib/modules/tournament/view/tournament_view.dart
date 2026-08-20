import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../data/models/tournament.dart';
import '../../../shared/tournament_display.dart';
import '../../../shared/widgets/checkers_background.dart';
import '../../../shared/widgets/checkers_gradient_button.dart';
import '../../../shared/widgets/checkers_square_icon_button.dart';
import '../../../shared/widgets/checkers_staggered_entrance.dart';
import '../../../themes/app_theme.dart';
import '../../../translations/translation_keys.dart';
import '../controller/tournament_controller.dart';
import 'widgets/bracket_view.dart';
import 'widgets/podium_view.dart';

class TournamentView extends GetView<TournamentController> {
  const TournamentView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;

    return Scaffold(
      body: CheckersBackground(
        child: SizedBox.expand(
          child: SafeArea(
            child: Obx(() {
              final detail = controller.detail.value;
              if (detail == null) {
                return Center(
                  child: CircularProgressIndicator(color: brand.brandGold),
                );
              }
              final summary = detail.summary;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                    child: Row(
                      children: [
                        IconButton(
                          key: const Key('tournament-back'),
                          onPressed: Get.back<void>,
                          icon: Icon(
                            Icons.arrow_back,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            TranslationKeys.tournamentNumber.trParams({
                              'number': '${summary.number}',
                            }),
                            style: theme.textTheme.headlineMedium!.copyWith(
                              color: brand.brandGold,
                              fontSize: 24,
                            ),
                          ),
                        ),
                        CheckersSquareIconButton(
                          icon: Icons.info_outline,
                          dimension: 42,
                          iconSize: 22,
                          tooltip: TranslationKeys.tournamentHowTitle.tr,
                          onPressed: () => showTournamentInstructions(context),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: summary.isFinished
                        ? TournamentPodium(detail: detail)
                        : Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: brand.brandGold,
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  tournamentStageLabel(summary.stage),
                                  style: theme.textTheme.bodyLarge!.copyWith(
                                    color: brand.brandGold,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                TranslationKeys.tournamentPlayersCount.trParams(
                                  {'count': '${summary.participantCount}'},
                                ),
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
                    if (!controller.myMatchReady.value) {
                      return const SizedBox(height: 8);
                    }
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                      child: CheckersGradientButton(
                        key: const Key('tournament-play-my-match'),
                        label: TranslationKeys.tournamentYourMatchReady.tr,
                        minHeight: 50,
                        onPressed: controller.playMyMatch,
                      ),
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Obx(() {
                      final mode = controller.viewMode.value;
                      return Row(
                        children: [
                          _ViewToggle(
                            label: TranslationKeys.tournamentFixtures.tr,
                            selected: mode == TournamentViewMode.fixtures,
                            onTap: () => controller.viewMode.value =
                                TournamentViewMode.fixtures,
                            keyName: 'tournament-view-fixtures',
                          ),
                          const SizedBox(width: 8),
                          _ViewToggle(
                            label: TranslationKeys.tournamentTable.tr,
                            selected: mode == TournamentViewMode.table,
                            onTap: () => controller.viewMode.value =
                                TournamentViewMode.table,
                            keyName: 'tournament-view-table',
                          ),
                        ],
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Obx(
                      () =>
                          controller.viewMode.value ==
                              TournamentViewMode.fixtures
                          ? _FixturesView(detail: detail)
                          : _TableView(detail: detail),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.keyName,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;
    return Expanded(
      child: InkWell(
        key: Key(keyName),
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? brand.brandGold
                  : theme.colorScheme.onPrimary.withValues(alpha: 0.5),
              width: selected ? 2 : 1,
            ),
            color: selected
                ? brand.brandGold.withValues(alpha: 0.14)
                : Colors.transparent,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge!.copyWith(
              color: selected
                  ? brand.brandGold
                  : theme.colorScheme.onPrimary.withValues(alpha: 0.8),
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

List<String> _orderedStages(TournamentDetail detail) {
  final stages = detail.matches.map((m) => m.stage).toSet().toList()
    ..sort(
      (a, b) => tournamentStageOrder(a).compareTo(tournamentStageOrder(b)),
    );
  return stages;
}

class _FixturesView extends GetView<TournamentController> {
  const _FixturesView({required this.detail});

  final TournamentDetail detail;

  @override
  Widget build(BuildContext context) {
    return TournamentBracket(detail: detail);
  }
}

class _TableView extends GetView<TournamentController> {
  const _TableView({required this.detail});

  final TournamentDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;
    final stages = _orderedStages(detail);
    final hasElimination = stages.contains('elimination');
    final standings = [...detail.players]
      ..sort((a, b) {
        final points = b.points.compareTo(a.points);
        if (points != 0) {
          return points;
        }
        final rating = b.rating.compareTo(a.rating);
        if (rating != 0) {
          return rating;
        }
        return a.joinOrder.compareTo(b.joinOrder);
      });

    String nameOf(String uid) => controller.playerOf(uid)?.nickname ?? '?';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        CheckersStaggeredEntrance(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          itemDelay: const Duration(milliseconds: 50),
          children: [
            if (hasElimination) ...[
              Text(
                TranslationKeys.tournamentStandings.tr,
                style: theme.textTheme.bodyLarge!.copyWith(
                  color: brand.brandGold,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  children: [
                    for (final (index, player) in standings.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 26,
                              child: Text(
                                '${index + 1}.',
                                style: theme.textTheme.bodyLarge!.copyWith(
                                  color: theme.colorScheme.onPrimary.withValues(
                                    alpha: 0.7,
                                  ),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                player.nickname,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge!.copyWith(
                                  color: player.eliminated
                                      ? theme.colorScheme.onPrimary.withValues(
                                          alpha: 0.5,
                                        )
                                      : theme.colorScheme.onPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              '${player.points} ${TranslationKeys.tournamentPts.tr}',
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
              const SizedBox(height: 14),
            ],
            for (final stage in stages) ...[
              Text(
                tournamentStageLabel(stage),
                style: theme.textTheme.bodyLarge!.copyWith(
                  color: brand.brandGold,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              for (final match in detail.matches.where((m) => m.stage == stage))
                InkWell(
                  key: Key('table-match-${match.id}'),
                  onTap: () => controller.openMatch(match),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.shadow.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.onPrimary.withValues(
                          alpha: 0.35,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${nameOf(match.p1Uid)}  vs  ${nameOf(match.p2Uid)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge!.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (match.isFinished)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.emoji_events,
                                size: 14,
                                color: brand.brandGold,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                nameOf(match.winnerUid ?? ''),
                                style: theme.textTheme.bodyLarge!.copyWith(
                                  color: brand.brandGold,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            TranslationKeys.tournamentLive.tr,
                            style: theme.textTheme.bodyLarge!.copyWith(
                              color: Colors.redAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ],
    );
  }
}
