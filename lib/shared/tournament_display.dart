import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../themes/app_theme.dart';
import '../translations/translation_keys.dart';
import 'widgets/checkers_modal.dart';

/// Localized display name for a tournament stage code.
String tournamentStageLabel(String stage) {
  switch (stage) {
    case 'elimination':
      return TranslationKeys.stageElimination.tr;
    case 'qf':
      return TranslationKeys.stageQuarterfinals.tr;
    case 'sf':
      return TranslationKeys.stageSemifinals.tr;
    case 'f':
      return TranslationKeys.stageFinal.tr;
    case 'third':
      return TranslationKeys.stageThirdPlace.tr;
    default:
      // 'r16', 'r32', ...
      final count = int.tryParse(stage.replaceFirst('r', ''));
      return count == null
          ? stage
          : TranslationKeys.stageRoundOf.trParams({'count': '$count'});
  }
}

/// Order used to lay out bracket columns.
int tournamentStageOrder(String stage) {
  switch (stage) {
    case 'elimination':
      return 0;
    case 'qf':
      return 80;
    case 'sf':
      return 90;
    case 'f':
      return 100;
    case 'third':
      return 101;
    default:
      final count = int.tryParse(stage.replaceFirst('r', '')) ?? 999;
      return 100 - count; // r32 < r16 < qf...
  }
}

/// "How tournaments work" modal (also linked from the lobby and bracket).
void showTournamentInstructions(BuildContext context) {
  showCheckersModal<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final brand = theme.extension<CheckersThemeExtension>()!;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckersModalHeader(
            title: TranslationKeys.tournamentHowTitle.tr,
            closeKey: const Key('tournament-instructions-close'),
            onClose: () => Navigator.of(dialogContext).pop(),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              child: Text(
                TranslationKeys.tournamentHowBody.tr,
                style: theme.textTheme.bodyLarge!.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontSize: 14.5,
                  height: 1.45,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            TranslationKeys.tournamentHowFooter.tr,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge!.copyWith(
              color: brand.brandGold,
              fontSize: 13,
            ),
          ),
        ],
      );
    },
  );
}
