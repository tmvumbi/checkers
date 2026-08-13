import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../shared/widgets/checkers_background.dart';
import '../../../themes/app_theme.dart';
import '../../../translations/translation_keys.dart';

/// Static rules explainer (native pages; kopo's video-based explainer is
/// intentionally not ported — PRD §5.7).
class HowToPlayView extends StatelessWidget {
  const HowToPlayView({super.key});

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
                      key: const Key('how-to-play-back'),
                      onPressed: Get.back<void>,
                      icon: Icon(
                        Icons.arrow_back,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                    Text(
                      TranslationKeys.howToPlay.tr,
                      style: theme.textTheme.headlineMedium!.copyWith(
                        color: brand.brandGold,
                        fontSize: 26,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: const [
                    _RuleCard(
                      icon: Icons.grid_4x4,
                      titleKey: TranslationKeys.htpBoardTitle,
                      bodyKey: TranslationKeys.htpBoardBody,
                    ),
                    _RuleCard(
                      icon: Icons.trending_up,
                      titleKey: TranslationKeys.htpMovesTitle,
                      bodyKey: TranslationKeys.htpMovesBody,
                    ),
                    _RuleCard(
                      icon: Icons.bolt,
                      titleKey: TranslationKeys.htpCaptureTitle,
                      bodyKey: TranslationKeys.htpCaptureBody,
                    ),
                    _RuleCard(
                      icon: Icons.workspace_premium,
                      titleKey: TranslationKeys.htpKingTitle,
                      bodyKey: TranslationKeys.htpKingBody,
                    ),
                    _RuleCard(
                      icon: Icons.handshake,
                      titleKey: TranslationKeys.htpDrawTitle,
                      bodyKey: TranslationKeys.htpDrawBody,
                    ),
                    _RuleCard(
                      icon: Icons.timer,
                      titleKey: TranslationKeys.htpClockTitle,
                      bodyKey: TranslationKeys.htpClockBody,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
  });

  final IconData icon;
  final String titleKey;
  final String bodyKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.shadow.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: brand.brandGold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titleKey.tr,
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: brand.brandGold,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            bodyKey.tr,
            style: theme.textTheme.bodyLarge!.copyWith(
              color: theme.colorScheme.onPrimary,
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
