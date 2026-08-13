import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../themes/app_theme.dart';

/// Full-bleed dark "game table" backdrop used by every screen, in place of
/// kopo's background image assets: a deep green-black gradient with a subtle
/// oversized checkerboard motif in the corner.
class CheckersBackground extends StatelessWidget {
  const CheckersBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brandTheme = Theme.of(context).extension<CheckersThemeExtension>()!;

    return DecoratedBox(
      decoration: BoxDecoration(gradient: brandTheme.tableGradient),
      child: CustomPaint(
        painter: const _BoardMotifPainter(),
        child: child,
      ),
    );
  }
}

class _BoardMotifPainter extends CustomPainter {
  const _BoardMotifPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 5;
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.024);
    // Oversized board corner fading out of the top-right of the screen.
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 5; col++) {
        if ((row + col).isEven) {
          continue;
        }
        canvas.drawRect(
          Rect.fromLTWH(
            size.width - (5 - col) * cell,
            (row - 1) * cell,
            cell,
            cell,
          ),
          paint,
        );
      }
    }
    final discPaint = Paint()..color = AppColors.gold.withValues(alpha: 0.05);
    canvas.drawCircle(
      Offset(size.width - cell * 1.5, cell * 1.5),
      cell * 0.38,
      discPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BoardMotifPainter oldDelegate) => false;
}
