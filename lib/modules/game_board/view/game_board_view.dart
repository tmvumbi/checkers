import 'package:flutter/material.dart';
import 'package:flutter_confetti/flutter_confetti.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_colors.dart';
import '../../../engine/checkers_engine.dart';
import '../../../engine/rules_config.dart';
import '../../../shared/seat_display.dart';
import '../../../shared/widgets/checkers_ad_banner.dart';
import '../../../shared/widgets/checkers_background.dart';
import '../../../shared/widgets/checkers_gradient_button.dart';
import '../../../shared/widgets/checkers_modal.dart';
import '../../../shared/widgets/checkers_square_icon_button.dart';
import '../../../themes/app_theme.dart';
import '../../../translations/translation_keys.dart';
import '../controller/game_board_controller.dart';
import '../models/game_board_arguments.dart';
import 'widgets/board_widget.dart';
import 'widgets/watchers_bar.dart';

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
                  const CheckersAdBanner(
                    key: Key('game-board-ad-banner'),
                    size: CheckersAdBannerSize.compactAdaptive,
                  ),
                  const SizedBox(height: 8),
                  _OpponentHeader(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Center(child: const BoardWidget()),
                    ),
                  ),
                  const _EmotePickerBar(),
                  _OwnHeader(),
                  const WatchersBar(),
                  const SizedBox(height: 4),
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
                        style: TextStyle(color: theme.colorScheme.onPrimary),
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

void _showRulesModal(BuildContext context, GameBoardController controller) {
  final rules = controller.args.rules;
  final presetLabel = switch (rules.preset) {
    RulesPreset.international => TranslationKeys.presetInternational.tr,
    RulesPreset.brazilian => TranslationKeys.presetBrazilian.tr,
    RulesPreset.american => TranslationKeys.presetAmerican.tr,
    RulesPreset.custom => TranslationKeys.presetCustom.tr,
  };
  final allowUndo = controller.isOnline
      ? (controller.snapshot.value?.allowUndo ?? false)
      : controller.args.allowUndo;
  final showUndoRow =
      controller.args.mode == GameBoardMode.pc ||
      (controller.snapshot.value?.vsPc ?? false);

  String onOff(bool value) =>
      value ? TranslationKeys.optionOn.tr : TranslationKeys.optionOff.tr;

  showCheckersModal<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final brand = theme.extension<CheckersThemeExtension>()!;

      Widget row(String label, String value) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodyLarge!.copyWith(
                  color: brand.brandGold,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckersModalHeader(
            title: TranslationKeys.rules.tr,
            closeKey: const Key('rules-modal-close'),
            onClose: () => Navigator.of(dialogContext).pop(),
          ),
          const SizedBox(height: 8),
          row('', presetLabel),
          row(
            TranslationKeys.boardSize.tr,
            '${rules.boardSize}x${rules.boardSize}',
          ),
          row(TranslationKeys.backwardCapture.tr, onOff(rules.backwardCapture)),
          row(TranslationKeys.flyingKing.tr, onOff(rules.flyingKing)),
          if (showUndoRow)
            row(TranslationKeys.allowUndoMoves.tr, onOff(allowUndo)),
        ],
      );
    },
  );
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
        final opponent = controller.spectatorLayout
            ? controller.playerOfColor(PieceColor.black)
            : controller.opponentPlayer;
        final name = controller.isOnline || controller.isReplay
            ? seatDisplayName(
                opponent,
                aiLevel: controller.snapshot.value?.aiLevel,
              )
            : 'PC (${difficultyLabel(controller.args.aiLevel!.name)})';
        final subtitle = controller.spectatorLayout
            ? ''
            : controller.isOnline && !controller.opponentConnected.value
            ? TranslationKeys.opponentDisconnected.tr
            : (controller.aiThinking.value ||
                      controller.activeAnimation.value != null
                  ? TranslationKeys.opponentTurn.tr
                  : (controller.isHumanTurn
                        ? TranslationKeys.yourTurn.tr
                        : ''));

        return Row(
          children: [
            _AvatarBadge(
              icon:
                  (!controller.isOnline && !controller.isReplay) ||
                      (opponent?.isBot ?? false)
                  ? Icons.smart_toy
                  : Icons.person,
              borderColor: theme.colorScheme.onPrimary,
              photoUrl: opponent?.photoUrl,
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
            _EmoteBubble(emote: controller.topEmote),
            _CapturedCountChip(
              byColor: controller.spectatorLayout
                  ? PieceColor.black
                  : (controller.humanColor == PieceColor.white
                        ? PieceColor.black
                        : PieceColor.white),
            ),
            const SizedBox(width: 4),
            if (controller.isOnline &&
                !(controller.snapshot.value?.vsPc ?? false))
              _ClockDisplay(isOwn: false, theme: theme, brand: brand)
            else if (controller.isOnline)
              const SizedBox(width: 26, height: 26)
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
      final isActive =
          snap != null &&
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
          Obx(() {
            controller.boardVersion.value;
            final white = controller.spectatorLayout
                ? controller.playerOfColor(PieceColor.white)
                : null;
            final photoUrl = controller.spectatorLayout
                ? white?.photoUrl
                : controller.ownPlayer?.photoUrl ??
                      controller.ownProfilePhotoUrl.value;
            return _AvatarBadge(
              icon: controller.spectatorLayout && (white?.isBot ?? false)
                  ? Icons.smart_toy
                  : Icons.person,
              borderColor: AppColors.gold,
              photoUrl: photoUrl,
            );
          }),
          _CapturedCountChip(
            byColor: controller.spectatorLayout
                ? PieceColor.white
                : controller.humanColor,
          ),
          _EmoteBubble(emote: controller.bottomEmote),
          const SizedBox(width: 12),
          Expanded(
            child: Obx(() {
              controller.boardVersion.value;
              final canUndo = controller.canUndo;
              if (controller.isReplay) {
                final white = controller.playerOfColor(PieceColor.white);
                final theme = Theme.of(context);
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Text(
                        seatDisplayName(
                          white,
                          aiLevel: controller.snapshot.value?.aiLevel,
                        ),
                        maxLines: 1,
                        style: theme.textTheme.bodyLarge!.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(width: 12),
                      CheckersSquareIconButton(
                        key: const Key('replay-prev'),
                        icon: Icons.skip_previous,
                        dimension: 44,
                        iconSize: 26,
                        tooltip: TranslationKeys.replayPrevious.tr,
                        onPressed: controller.replayIndex.value > 0
                            ? controller.replayPrev
                            : null,
                      ),
                      const SizedBox(width: 8),
                      CheckersSquareIconButton(
                        key: const Key('replay-play'),
                        icon: controller.replayPlaying.value
                            ? Icons.pause
                            : Icons.play_arrow,
                        dimension: 44,
                        iconSize: 26,
                        tooltip: TranslationKeys.replayPlay.tr,
                        onPressed: controller.replayTogglePlay,
                      ),
                      const SizedBox(width: 8),
                      CheckersSquareIconButton(
                        key: const Key('replay-next'),
                        icon: Icons.skip_next,
                        dimension: 44,
                        iconSize: 26,
                        tooltip: TranslationKeys.replayNext.tr,
                        onPressed:
                            controller.replayIndex.value <
                                controller.replayTotal.value
                            ? controller.replayNext
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${controller.replayIndex.value}'
                        '/${controller.replayTotal.value}',
                        key: const Key('replay-counter'),
                        style: theme.textTheme.bodyLarge!.copyWith(
                          color: theme
                              .extension<CheckersThemeExtension>()!
                              .brandGold,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                );
              }
              if (controller.isWatching) {
                final white = controller.playerOfColor(PieceColor.white);
                final theme = Theme.of(context);
                return Row(
                  children: [
                    CheckersSquareIconButton(
                      key: const Key('game-rules-button'),
                      icon: Icons.info_outline,
                      dimension: 46,
                      iconSize: 26,
                      tooltip: TranslationKeys.rules.tr,
                      onPressed: () => _showRulesModal(context, controller),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        seatDisplayName(
                          white,
                          aiLevel: controller.snapshot.value?.aiLevel,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge!.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    if (!(controller.snapshot.value?.vsPc ?? false)) ...[
                      _ClockDisplay(
                        isOwn: true,
                        theme: theme,
                        brand: theme.extension<CheckersThemeExtension>()!,
                      ),
                      const SizedBox(width: 10),
                    ],
                    const _LeaveWatchButton(),
                  ],
                );
              }
              // scaleDown keeps the button row fitting on narrow phones.
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    if (!controller.isOnline && controller.args.allowUndo) ...[
                      CheckersSquareIconButton(
                        key: const Key('game-undo-button'),
                        icon: Icons.undo,
                        dimension: 46,
                        iconSize: 26,
                        tooltip: TranslationKeys.undoMove.tr,
                        onPressed: canUndo ? controller.undoLastExchange : null,
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
                    const SizedBox(width: 10),
                    CheckersSquareIconButton(
                      key: const Key('game-rules-button'),
                      icon: Icons.info_outline,
                      dimension: 46,
                      iconSize: 26,
                      tooltip: TranslationKeys.rules.tr,
                      onPressed: () => _showRulesModal(context, controller),
                    ),
                    if (controller.canSendEmotes) ...[
                      const SizedBox(width: 10),
                      CheckersSquareIconButton(
                        key: const Key('game-emote-button'),
                        icon: Icons.emoji_emotions_outlined,
                        dimension: 46,
                        iconSize: 26,
                        tooltip: TranslationKeys.sendEmote.tr,
                        onPressed: controller.emotePickerOpen.toggle,
                      ),
                    ],
                    const SizedBox(width: 10),
                    if (controller.isOnline &&
                        !(controller.snapshot.value?.vsPc ?? false))
                      _ClockDisplay(
                        isOwn: true,
                        theme: Theme.of(context),
                        brand: Theme.of(
                          context,
                        ).extension<CheckersThemeExtension>()!,
                      ),
                  ],
                ),
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

class _LeaveWatchButton extends StatelessWidget {
  const _LeaveWatchButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.onPrimary.withValues(alpha: 0.72),
          width: 2,
        ),
        color: theme.colorScheme.shadow.withValues(alpha: 0.35),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('game-leave-watch'),
          onTap: Get.back<void>,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.logout,
                  size: 22,
                  color: theme.colorScheme.onPrimary,
                ),
                const SizedBox(width: 6),
                Text(
                  TranslationKeys.leaveGame.tr,
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Explicit emoji fallback (Inter has no emoji glyphs). Note: iOS 17.4+
/// *simulators* show tofu because Flutter cannot parse their new emoji
/// font format — real devices render fine.
const TextStyle _emojiStyle = TextStyle(
  fontSize: 24,
  fontFamilyFallback: ['Apple Color Emoji', 'Noto Color Emoji'],
);

/// Briefly floats a received emoji next to a player header.
class _EmoteBubble extends StatelessWidget {
  const _EmoteBubble({required this.emote});

  final RxnString emote;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final emoji = emote.value;
      return AnimatedScale(
        scale: emoji == null ? 0 : 1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        child: emoji == null
            ? const SizedBox(width: 0, height: 34)
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(emoji, style: _emojiStyle.copyWith(fontSize: 28)),
              ),
      );
    });
  }
}

/// Horizontal emoji picker shown above the bottom header while open.
class _EmotePickerBar extends GetView<GameBoardController> {
  const _EmotePickerBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      if (!controller.emotePickerOpen.value) {
        return const SizedBox.shrink();
      }
      return Container(
        key: const Key('emote-picker'),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.shadow.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: theme.colorScheme.onPrimary.withValues(alpha: 0.5),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final emoji in GameBoardController.emoteChoices)
                InkWell(
                  key: Key('emote-$emoji'),
                  customBorder: const CircleBorder(),
                  onTap: () => controller.sendEmote(emoji),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Text(emoji, style: _emojiStyle),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

/// "Pieces taken" chip: a mini disc in the captured side's colors + count.
class _CapturedCountChip extends GetView<GameBoardController> {
  const _CapturedCountChip({required this.byColor});

  /// The player whose captures are counted.
  final PieceColor byColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      controller.boardVersion.value;
      final count = controller.capturedBy(byColor);
      final capturedIsWhite = byColor == PieceColor.black;
      return Container(
        key: Key('captured-count-${byColor.name}'),
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.shadow.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: theme.colorScheme.onPrimary.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: capturedIsWhite
                    ? AppColors.pieceLight
                    : AppColors.pieceDark,
                border: Border.all(
                  color: capturedIsWhite
                      ? AppColors.pieceLightEdge
                      : AppColors.pieceDarkEdge,
                  width: 2,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '×$count',
              style: theme.textTheme.bodyLarge!.copyWith(
                color: theme.colorScheme.onPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({
    required this.icon,
    required this.borderColor,
    this.photoUrl,
  });

  final IconData icon;
  final Color borderColor;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = photoUrl;
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
        color: theme.colorScheme.shadow.withValues(alpha: 0.35),
        image: url == null
            ? null
            : DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
      ),
      child: url == null
          ? Icon(icon, color: theme.colorScheme.onPrimary)
          : null,
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
    if (controller.isWatching) {
      final winner = controller.playerOfColor(
        controller.result.value == GameResult.whiteWin
            ? PieceColor.white
            : PieceColor.black,
      );
      return TranslationKeys.spectatorWinner.trParams({
        'name': winner?.nickname ?? '',
      });
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
    if (humanWon && !controller.isWatching) {
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
              border: Border.all(color: theme.colorScheme.onPrimary, width: 2),
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
                if (controller.isWatching)
                  const SizedBox.shrink()
                else if (controller.isOnline)
                  Obx(() {
                    final waiting = controller.rematchRequested.value;
                    final opponentWants = controller.opponentWantsRematch.value;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (opponentWants && !waiting)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              TranslationKeys.opponentWantsRematch.tr,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge!
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
                          onPressed: waiting ? null : controller.requestRematch,
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
