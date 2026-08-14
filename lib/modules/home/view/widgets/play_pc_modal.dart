import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../engine/ai/ai_config.dart';
import '../../../../engine/checkers_engine.dart';
import '../../../../engine/rules_config.dart';
import '../../../../routes/app_routes.dart';
import '../../../../shared/widgets/checkers_gradient_button.dart';
import '../../../../shared/widgets/checkers_modal.dart';
import '../../../../themes/app_theme.dart';
import '../../../../translations/translation_keys.dart';
import '../../../game_board/models/game_board_arguments.dart';

enum _SideChoice { white, black, random }

/// "Play with PC" setup: difficulty, rules preset + toggles, side.
class PlayPcModalContent extends StatefulWidget {
  const PlayPcModalContent({super.key});

  @override
  State<PlayPcModalContent> createState() => _PlayPcModalContentState();
}

class _PlayPcModalContentState extends State<PlayPcModalContent> {
  AiLevel _level = AiLevel.medium;
  int _boardSize = 10;
  bool _backwardCapture = true;
  bool _flyingKing = true;
  bool _allowUndo = false;
  _SideChoice _side = _SideChoice.white;

  RulesConfig get _rules => RulesConfig(
    boardSize: _boardSize,
    backwardCapture: _backwardCapture,
    flyingKing: _flyingKing,
    majorityCapture: _backwardCapture,
  );

  void _applyPreset(RulesConfig preset) {
    setState(() {
      _boardSize = preset.boardSize;
      _backwardCapture = preset.backwardCapture;
      _flyingKing = preset.flyingKing;
    });
  }

  void _start() {
    final humanColor = switch (_side) {
      _SideChoice.white => PieceColor.white,
      _SideChoice.black => PieceColor.black,
      _SideChoice.random =>
        Random().nextBool() ? PieceColor.white : PieceColor.black,
    };
    Navigator.of(context).pop();
    Get.toNamed<void>(
      AppRoutes.gameBoard,
      arguments: GameBoardArguments.pc(
        rules: _rules,
        aiLevel: _level,
        humanColor: humanColor,
        allowUndo: _allowUndo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preset = _rules.preset;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckersModalHeader(
            title: TranslationKeys.playWithPc.tr,
            closeKey: const Key('play-pc-close'),
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 16),
          _SectionLabel(text: TranslationKeys.difficulty.tr),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final level in AiLevel.values) ...[
                Expanded(
                  child: _ChoiceChip(
                    key: Key('play-pc-level-${level.name}'),
                    label: switch (level) {
                      AiLevel.easy => TranslationKeys.difficultyEasy.tr,
                      AiLevel.medium => TranslationKeys.difficultyMedium.tr,
                      AiLevel.hard => TranslationKeys.difficultyHard.tr,
                    },
                    selected: _level == level,
                    onTap: () => setState(() => _level = level),
                  ),
                ),
                if (level != AiLevel.values.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _SectionLabel(text: TranslationKeys.rules.tr),
          const SizedBox(height: 8),
          _ChoiceChip(
            key: const Key('play-pc-preset-international'),
            label: TranslationKeys.presetInternational.tr,
            selected: preset == RulesPreset.international,
            onTap: () => _applyPreset(RulesConfig.international),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ChoiceChip(
                  key: const Key('play-pc-preset-brazilian'),
                  label: TranslationKeys.presetBrazilian.tr,
                  selected: preset == RulesPreset.brazilian,
                  onTap: () => _applyPreset(RulesConfig.brazilian),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ChoiceChip(
                  key: const Key('play-pc-preset-american'),
                  label: TranslationKeys.presetAmerican.tr,
                  selected: preset == RulesPreset.american,
                  onTap: () => _applyPreset(RulesConfig.american),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ToggleRow(
            label: TranslationKeys.boardSize.tr,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MiniChip(
                  key: const Key('play-pc-size-10'),
                  label: '10x10',
                  selected: _boardSize == 10,
                  onTap: () => setState(() => _boardSize = 10),
                ),
                const SizedBox(width: 6),
                _MiniChip(
                  key: const Key('play-pc-size-8'),
                  label: '8x8',
                  selected: _boardSize == 8,
                  onTap: () => setState(() => _boardSize = 8),
                ),
              ],
            ),
          ),
          _SwitchRow(
            key: const Key('play-pc-backward-capture'),
            label: TranslationKeys.backwardCapture.tr,
            value: _backwardCapture,
            onChanged: (value) => setState(() => _backwardCapture = value),
          ),
          _SwitchRow(
            key: const Key('play-pc-flying-king'),
            label: TranslationKeys.flyingKing.tr,
            value: _flyingKing,
            onChanged: (value) => setState(() => _flyingKing = value),
          ),
          _SwitchRow(
            key: const Key('play-pc-allow-undo'),
            label: TranslationKeys.allowUndoMoves.tr,
            value: _allowUndo,
            onChanged: (value) => setState(() => _allowUndo = value),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final side in _SideChoice.values) ...[
                Expanded(
                  child: _ChoiceChip(
                    key: Key('play-pc-side-${side.name}'),
                    label: switch (side) {
                      _SideChoice.white => TranslationKeys.playAsWhite.tr,
                      _SideChoice.black => TranslationKeys.playAsBlack.tr,
                      _SideChoice.random => TranslationKeys.playAsRandom.tr,
                    },
                    selected: _side == side,
                    onTap: () => setState(() => _side = side),
                  ),
                ),
                if (side != _SideChoice.values.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 18),
          CheckersGradientButton(
            key: const Key('play-pc-start'),
            label: TranslationKeys.startGame.tr,
            onPressed: _start,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyLarge!.copyWith(
        color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.shadow.withValues(
            alpha: selected ? 0.5 : 0.25,
          ),
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
            color: selected ? brand.brandGold : theme.colorScheme.onPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? brand.brandGold
                : theme.colorScheme.onPrimary.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodyLarge!.copyWith(
            color: selected ? brand.brandGold : theme.colorScheme.onPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.label, required this.trailing});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
          trailing,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;
    return _ToggleRow(
      label: label,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: brand.brandGold.withValues(alpha: 0.6),
        thumbColor: WidgetStatePropertyAll(theme.colorScheme.onPrimary),
      ),
    );
  }
}
