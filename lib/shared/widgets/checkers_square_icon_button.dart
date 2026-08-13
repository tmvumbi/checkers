import 'package:flutter/material.dart';

class CheckersSquareIconButton extends StatelessWidget {
  const CheckersSquareIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    super.key,
    this.dimension = 58,
    this.iconSize = 38,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double dimension;
  final double iconSize;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox.square(
      dimension: dimension,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.onPrimary.withValues(alpha: 0.72),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.34),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(
            icon,
            color: iconColor ?? theme.colorScheme.onPrimary,
            size: iconSize,
          ),
          tooltip: tooltip,
        ),
      ),
    );
  }
}
