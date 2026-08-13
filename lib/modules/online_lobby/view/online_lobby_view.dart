import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../shared/widgets/checkers_background.dart';
import '../../../shared/widgets/checkers_gradient_button.dart';
import '../../../themes/app_theme.dart';
import '../../../translations/translation_keys.dart';
import '../controller/online_lobby_controller.dart';

class OnlineLobbyView extends GetView<OnlineLobbyController> {
  const OnlineLobbyView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;

    return Scaffold(
      body: CheckersBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Obx(() {
                  final snap = controller.snapshot.value;
                  final failed = controller.failed.value;
                  final seated = snap?.players.length ?? 1;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        TranslationKeys.lobbyTitle.tr,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium!.copyWith(
                          color: brand.brandGold,
                          fontSize: 26,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        failed
                            ? TranslationKeys.lobbyFailed.tr
                            : TranslationKeys.lobbyWaiting.tr,
                        key: const Key('lobby-status'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge!.copyWith(
                          color: theme.colorScheme.onPrimary.withValues(
                            alpha: 0.85,
                          ),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _SeatSlot(filled: true, theme: theme),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 18),
                            child: Text(
                              'VS',
                              style: theme.textTheme.headlineMedium!.copyWith(
                                color: brand.brandGold,
                                fontSize: 22,
                              ),
                            ),
                          ),
                          _SeatSlot(filled: seated >= 2, theme: theme),
                        ],
                      ),
                      const SizedBox(height: 36),
                      if (!failed)
                        Center(
                          child: SizedBox(
                            width: 30,
                            height: 30,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.6,
                              color: brand.brandGold,
                            ),
                          ),
                        ),
                      const SizedBox(height: 36),
                      CheckersGradientButton(
                        key: const Key('lobby-leave'),
                        label: TranslationKeys.lobbyLeave.tr,
                        gradientStyle: CheckersGradientButtonStyle.logo,
                        onPressed: controller.leaveLobby,
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeatSlot extends StatelessWidget {
  const _SeatSlot({required this.filled, required this.theme});

  final bool filled;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.shadow.withValues(alpha: 0.35),
        border: Border.all(
          color: filled
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onPrimary.withValues(alpha: 0.35),
          width: 2,
        ),
      ),
      child: Icon(
        filled ? Icons.person : Icons.hourglass_empty,
        size: 40,
        color: theme.colorScheme.onPrimary.withValues(
          alpha: filled ? 0.95 : 0.4,
        ),
      ),
    );
  }
}
