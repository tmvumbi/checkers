import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../data/models/block_status.dart';
import '../../../shared/widgets/checkers_background.dart';
import '../../../themes/app_theme.dart';
import '../../../translations/translation_keys.dart';

/// Full-block wall: the player only learns that they are blocked and for
/// how long. No navigation out.
class BlockedView extends StatelessWidget {
  const BlockedView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandTheme = theme.extension<CheckersThemeExtension>()!;
    final status = Get.arguments is BlockStatus
        ? Get.arguments as BlockStatus
        : BlockStatus.none;

    final message = status.permanent || status.expiresAt == null
        ? TranslationKeys.blockedPermanentMessage.tr
        : TranslationKeys.blockedUntilMessage.trParams({
            'date': _formatDate(status.expiresAt!),
          });

    return Scaffold(
      body: CheckersBackground(
        child: SizedBox.expand(
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.gpp_bad_outlined,
                        size: 72,
                        color: brandTheme.brandGold,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        TranslationKeys.blockedTitle.tr,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium!.copyWith(
                          color: brandTheme.brandGold,
                          fontSize: 26,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        message,
                        key: const Key('blocked-message'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge!.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 16,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${pad(date.month)}-${pad(date.day)} '
        '${pad(date.hour)}:${pad(date.minute)}';
  }
}
