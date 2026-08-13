import 'package:flutter/material.dart';

import '../../themes/app_theme.dart';

enum CheckersGradientButtonStyle { primary, logo }

class CheckersGradientButton extends StatelessWidget {
  const CheckersGradientButton({
    required this.label,
    required this.onPressed,
    this.gradientStyle = CheckersGradientButtonStyle.primary,
    this.minHeight = 64,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final CheckersGradientButtonStyle gradientStyle;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandTheme = theme.extension<CheckersThemeExtension>()!;
    final gradient = switch (gradientStyle) {
      CheckersGradientButtonStyle.primary => brandTheme.primaryButtonGradient,
      CheckersGradientButtonStyle.logo => brandTheme.logoGradient,
    };
    final isEnabled = onPressed != null;

    return Opacity(
      opacity: isEnabled ? 1 : 0.58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.onPrimary, width: 2),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.22),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Center(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge!.copyWith(
                    color: theme.colorScheme.onPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
