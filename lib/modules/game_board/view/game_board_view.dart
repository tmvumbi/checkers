import 'package:flutter/material.dart';
import 'package:flutter_confetti/flutter_confetti.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_colors.dart';
import '../../../engine/ai/ai_config.dart';
import '../../../engine/checkers_engine.dart';
import '../../../shared/widgets/checkers_background.dart';
import '../../../shared/widgets/checkers_gradient_button.dart';
import '../../../shared/widgets/checkers_modal.dart';
import '../../../shared/widgets/checkers_square_icon_button.dart';
import '../../../themes/app_theme.dart';
import '../../../translations/translation_keys.dart';
import '../controller/game_board_controller.dart';
import '../models/game_board_arguments.dart';
import 'widgets/board_widget.dart';

class GameBoardView extends GetView<GameBoardController> {
  const GameBoardView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CheckersBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  const SizedBox(height: 8),
                  _OpponentHeader(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Center(child: const BoardWidget()),
                    ),
                  ),
                  _OwnHeader(),
                  const SizedBox(height: 8),
                ],
              ),
              const _DrawOfferBanner(),
              const _GameOverOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawOfferBanner extends GetView<GameBoardController> {
  const _DrawOfferBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;
    return Obx(() {
      final incoming = controller.incomingDrawOffer.value;
      final pending = controller.drawOfferPending.value;
      if (!incoming && !pending) {
        return const SizedBox.shrink();
      }
      return Positioned(
        top: 64,
        left: 20,
        right: 20,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.shadow.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: brand.brandGold, width: 2),
          ),
          child: incoming
              ? Row(
                  children: [
                    Expanded(
                      child: Text(
                        TranslationKeys.drawOfferedByOpponent.tr,
                        style: theme.textTheme.bodyLarge!.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    TextButton(
                      key: const Key('draw-accept'),
                      onPressed: () => controller.respondDraw(true),
                      child: Text(
                        TranslationKeys.accept.tr,
                        style: TextStyle(color: brand.brandGold),
                      ),
                    ),
                    TextButton(
                      key: const Key('draw-decline'),
                      onPressed: () => controller.respondDraw(false),
                      child: Text(
                        TranslationKeys.decline.tr,
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                )
              : Text(
                  TranslationKeys.drawOfferSent.tr,
                  key: const Key('draw-pending-label'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 14,
                  ),
                ),
        ),
      );
    });
  }
}

class _OpponentHeader extends GetView<GameBoardController> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Obx(() {
        controller.boardVersion.value;
        final opponent = controller.opponentPlayer;
        final name = controller.isOnline
            ? (opponent?.nickname ?? '…')
            : 'PC — ${switch (controller.args.aiLevel!) {
                AiLevel.easy => TranslationKeys.difficultyEasy.tr,
                AiLevel.medium => TranslationKeys.difficultyMedium.tr,
                AiLevel.hard => TranslationKeys.difficultyHard.tr,
              }}';
        final subtitle = controller.isOnline &&
                !controller.opponentConnected.value
            ? TranslationKeys.opponentDisconnected.tr
            : (controller.aiThinking.value ||
                    controller.activeAnimation.value != null
                ? TranslationKeys.opponentTurn.tr
                : (controller.isHumanTurn ? TranslationKeys.yourTurn.tr : ''));

        return Row(
          children: [
            _AvatarBadge(
              icon: controller.isOnline ? Icons.person : Icons.smart_toy,
              borderColor: theme.colorScheme.onPrimary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge!.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 17,
                    ),
                  ),
                  Text(
                    subtitle,
                    key: const Key('game-turn-label'),
                    style: theme.textTheme.bodyLarge!.copyWith(
                      color: brand.brandGold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            if (controller.isOnline)
              _ClockDisplay(
                isOwn: false,
                theme: theme,
                brand: brand,
              )
            else
              Obx(() {
                if (!controller.aiThinking.value) {
                  return const SizedBox(width: 26, height: 26);
                }
                return SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: brand.brandGold,
                  ),
                );
              }),
          ],
        );
      }),
    );
  }
}

class _ClockDisplay extends GetView<GameBoardController> {
  const _ClockDisplay({
    required this.isOwn,
    required this.theme,
    required this.brand,
  });

  final bool isOwn;
  final ThemeData theme;
  final CheckersThemeExtension brand;

  String _format(int ms) {
    final totalSeconds = (ms / 1000).ceil();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final snap = controller.snapshot.value;
      final bank = isOwn
          ? controller.ownBankMs.value
          : controller.opponentBankMs.value;
      final isActive = snap != null &&
          snap.isPlaying &&
          (snap.sideToMove == controller.humanColor) == isOwn;
      final turnRemaining = controller.turnRemainingMs.value;
      final lowBank = bank < 30000;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.shadow.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? brand.brandGold
                : theme.colorScheme.onPrimary.withValues(alpha: 0.4),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive)
              Text(
                '${(turnRemaining / 1000).ceil()}s',
                key: Key(isOwn ? 'clock-own-turn' : 'clock-opp-turn'),
                style: theme.textTheme.bodyLarge!.copyWith(
                  color: brand.brandGold,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            Text(
              _format(bank),
              key: Key(isOwn ? 'clock-own-bank' : 'clock-opp-bank'),
              style: theme.textTheme.bodyLarge!.copyWith(
                color: lowBank
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.onPrimary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _OwnHeader extends GetView<GameBoardController> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _AvatarBadge(
            icon: Icons.person,
            borderColor: AppColors.gold,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Obx(() {
              controller.boardVersion.value;
              final canUndo = controller.canUndo;
              return Row(
                children: [
                  if (!controller.isOnline) ...[
                    CheckersSquareIconButton(
                      key: const Key('game-undo-button'),
                      icon: Icons.undo,
                      dimension: 46,
                      iconSize: 26,
                      tooltip: TranslationKeys.undoMove.tr,
                      onPressed:
                          canUndo ? controller.undoLastExchange : null,
                    ),
                    const SizedBox(width: 10),
                  ],
                  CheckersSquareIconButton(
                    key: const Key('game-resign-button'),
                    icon: Icons.flag_outlined,
                    dimension: 46,
                    iconSize: 26,
                    tooltip: TranslationKeys.resign.tr,
                    onPressed: controller.result.value == GameResult.ongoing
                        ? () => _confirmResign(context)
                        : null,
                  ),
                  if (controller.isOnline) ...[
                    const SizedBox(width: 10),
                    CheckersSquareIconButton(
                      key: const Key('game-draw-button'),
                      icon: Icons.handshake_outlined,
                      dimension: 46,
                      iconSize: 26,
                      tooltip: TranslationKeys.offerDraw.tr,
                      onPressed: controller.canOfferDraw
                          ? controller.offerDraw
                          : null,
                    ),
                  ],
                  const Spacer(),
                  if (controller.isOnline)
                    _ClockDisplay(
                      isOwn: true,
                      theme: Theme.of(context),
                      brand: Theme.of(context)
                          .extension<CheckersThemeExtension>()!,
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  void _confirmResign(BuildContext context) {
    showCheckersModal<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              TranslationKeys.resignConfirmTitle.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium!.copyWith(
                color: theme.extension<CheckersThemeExtension>()!.brandGold,
                fontSize: 24,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              TranslationKeys.resignConfirmMessage.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge!.copyWith(
                color: theme.colorScheme.onPrimary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 20),
            CheckersGradientButton(
              key: const Key('game-resign-confirm'),
              label: TranslationKeys.confirm.tr,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                controller.resign();
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
}

class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({required this.icon, required this.borderColor});

  final IconData icon;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
        color: theme.colorScheme.shadow.withValues(alpha: 0.35),
      ),
      child: Icon(icon, color: theme.colorScheme.onPrimary),
    );
  }
}

class _GameOverOverlay extends GetView<GameBoardController> {
  const _GameOverOverlay();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final result = controller.result.value;
      if (result == GameResult.ongoing) {
        return const SizedBox.shrink();
      }
      return _GameOverBanner(
        humanWon: controller.humanWon,
        isDraw: result == GameResult.draw,
        reason: controller.resultReason.value,
      );
    });
  }
}

class _GameOverBanner extends GetView<GameBoardController> {
  const _GameOverBanner({
    required this.humanWon,
    required this.isDraw,
    required this.reason,
  });

  final bool humanWon;
  final bool isDraw;
  final ResultReason reason;

  String get _title {
    if (isDraw) {
      return TranslationKeys.draw.tr;
    }
    return humanWon ? TranslationKeys.youWon.tr : TranslationKeys.youLost.tr;
  }

  String get _subtitle {
    return switch (reason) {
      ResultReason.noPieces => TranslationKeys.winReasonNoPieces.tr,
      ResultReason.blocked => TranslationKeys.winReasonBlocked.tr,
      ResultReason.resignation => TranslationKeys.winReasonResignation.tr,
      ResultReason.timeout => TranslationKeys.winReasonTimeout.tr,
      ResultReason.abandonment => TranslationKeys.winReasonAbandonment.tr,
      ResultReason.agreement => TranslationKeys.drawReasonAgreement.tr,
      ResultReason.repetition => TranslationKeys.drawReasonRepetition.tr,
      ResultReason.kingMoves25 => TranslationKeys.drawReason25Moves.tr,
      ResultReason.endgame16 => TranslationKeys.drawReason16Moves.tr,
      ResultReason.endgame5 => TranslationKeys.drawReason5Moves.tr,
      ResultReason.noProgress40 => TranslationKeys.drawReason40Moves.tr,
      ResultReason.none => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;
    if (humanWon) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Confetti.launch(
          context,
          options: const ConfettiOptions(particleCount: 56, spread: 80),
        );
      });
    }

    return Positioned.fill(
      child: ColoredBox(
        color: theme.colorScheme.shadow.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.shadow.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.onPrimary,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _title,
                  key: const Key('game-over-title'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium!.copyWith(
                    color: brand.brandGold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _subtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 20),
                if (controller.isOnline)
                  Obx(() {
                    final waiting = controller.rematchRequested.value;
                    final opponentWants =
                        controller.opponentWantsRematch.value;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (opponentWants && !waiting)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              TranslationKeys.opponentWantsRematch.tr,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge!
                                  .copyWith(
                                    color: Theme.of(context)
                                        .extension<CheckersThemeExtension>()!
                                        .brandGold,
                                    fontSize: 14,
                                  ),
                            ),
                          ),
                        CheckersGradientButton(
                          key: const Key('game-rematch'),
                          label: waiting
                              ? TranslationKeys.rematchWaiting.tr
                              : TranslationKeys.rematch.tr,
                          onPressed:
                              waiting ? null : controller.requestRematch,
                        ),
                      ],
                    );
                  })
                else
                  CheckersGradientButton(
                    key: const Key('game-play-again'),
                    label: TranslationKeys.playAgain.tr,
                    onPressed: controller.playAgain,
                  ),
                const SizedBox(height: 10),
                CheckersGradientButton(
                  key: const Key('game-back-home'),
                  label: TranslationKeys.backHome.tr,
                  gradientStyle: CheckersGradientButtonStyle.logo,
                  onPressed: controller.goHome,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// The arguments type is part of this view's public contract.
typedef GameBoardViewArguments = GameBoardArguments;
