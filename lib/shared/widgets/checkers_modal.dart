import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../themes/app_theme.dart';
import '../../translations/translation_keys.dart';
import 'checkers_gradient_button.dart';

Future<T?> showCheckersModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return CheckersModal(child: builder(dialogContext));
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return FadeTransition(
        opacity: curvedAnimation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}

class CheckersModal extends StatelessWidget {
  const CheckersModal({
    required this.child,
    super.key,
    this.maxWidth = 330,
    this.padding = const EdgeInsets.symmetric(horizontal: 32),
    this.contentPadding = const EdgeInsets.fromLTRB(24, 16, 24, 30),
    this.borderRadius = 20,
    this.blurSigma = 7,
    this.backdropOpacity = 0.62,
    this.panelOpacity = 0.42,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry contentPadding;
  final double borderRadius;
  final double blurSigma;
  final double backdropOpacity;
  final double panelOpacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      type: MaterialType.transparency,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: ColoredBox(
          color: theme.colorScheme.shadow.withValues(alpha: backdropOpacity),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: padding,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.shadow.withValues(
                        alpha: panelOpacity,
                      ),
                      borderRadius: BorderRadius.circular(borderRadius),
                      border: Border.all(
                        color: theme.colorScheme.onPrimary,
                        width: 2,
                      ),
                    ),
                    child: Padding(padding: contentPadding, child: child),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Standard modal header: centered gold title with an optional X close
/// button. Confirmation dialogs with explicit Cancel buttons skip the X.
class CheckersModalHeader extends StatelessWidget {
  const CheckersModalHeader({
    required this.title,
    this.onClose,
    this.closeKey,
    super.key,
  });

  final String title;
  final VoidCallback? onClose;
  final Key? closeKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;

    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium!.copyWith(
            color: brand.brandGold,
            fontSize: 24,
          ),
        ),
        if (onClose != null)
          Positioned(
            right: -8,
            child: IconButton(
              key: closeKey,
              onPressed: onClose,
              icon: Icon(Icons.close, color: theme.colorScheme.onPrimary),
              tooltip: TranslationKeys.close.tr,
            ),
          ),
      ],
    );
  }
}

class CheckersMessageModalContent extends StatelessWidget {
  const CheckersMessageModalContent({
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onClose,
    this.closeTooltip,
    super.key,
  });

  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onClose;
  final String? closeTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandTheme = theme.extension<CheckersThemeExtension>()!;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: onClose,
              icon: Icon(Icons.close, color: theme.colorScheme.onPrimary),
              tooltip: closeTooltip,
            ),
          ),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium!.copyWith(
              color: brandTheme.brandGold,
              fontSize: 28,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge!.copyWith(
              color: theme.colorScheme.onPrimary,
              fontSize: 18,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 26),
          CheckersGradientButton(label: buttonLabel, onPressed: onClose),
        ],
      ),
    );
  }
}
