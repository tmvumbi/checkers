import 'package:flutter/material.dart';
import 'package:flutter_confetti/flutter_confetti.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_colors.dart';
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
              const _GameOverOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpponentHeader extends GetView<GameBoardController> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;
    final levelKey = switch (controller.args.aiLevel) {
      null => TranslationKeys.playWithPeople,
      _ => switch (controller.args.aiLevel!.name) {
        'easy' => TranslationKeys.difficultyEasy,
        'medium' => TranslationKeys.difficultyMedium,
        _ => TranslationKeys.difficultyHard,
      },
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _AvatarBadge(
            icon: Icons.smart_toy,
            borderColor: theme.colorScheme.onPrimary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PC — ${levelKey.tr}',
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 17,
                  ),
                ),
                Obx(
                  () => Text(
                    controller.aiThinking.value ||
                            controller.activeAnimation.value != null
                        ? TranslationKeys.opponentTurn.tr
                        : (controller.isHumanTurn
                              ? TranslationKeys.yourTurn.tr
                              : ''),
                    key: const Key('game-turn-label'),
                    style: theme.textTheme.bodyLarge!.copyWith(
                      color: brand.brandGold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
      ),
    );
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
