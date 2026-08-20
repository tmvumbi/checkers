import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';
import '../../core/constants/app_strings.dart';
import '../../themes/app_theme.dart';
import '../../translations/translation_keys.dart';

/// Animated brand mark, in the spirit of kopo's card-fan logo: a 2x2 board
/// tile with two pieces pops in with an elastic curve while the wordmark
/// bounces into its gradient plate.
class CheckersLogoMark extends StatefulWidget {
  const CheckersLogoMark({super.key, this.compact = false});

  final bool compact;

  @override
  State<CheckersLogoMark> createState() => _CheckersLogoMarkState();
}

class _CheckersLogoMarkState extends State<CheckersLogoMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _tileScale;
  late final Animation<double> _wordmarkScale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();
    _tileScale = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.62, curve: Curves.elasticOut),
    );
    _wordmarkScale = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 1, curve: Curves.bounceOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandTheme = theme.extension<CheckersThemeExtension>()!;
    final tileSize = widget.compact ? 64.0 : 96.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: _tileScale,
          child: _BoardTile(size: tileSize),
        ),
        SizedBox(height: widget.compact ? 10 : 16),
        ScaleTransition(
          scale: _wordmarkScale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: brandTheme.logoGradient,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.onPrimary,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.shadow.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.compact ? 14 : 22,
                    vertical: widget.compact ? 6 : 10,
                  ),
                  // FittedBox keeps longer wordmarks (FR "JEU DE DAME") on one
                  // line on narrow screens.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      TranslationKeys.appWordmark.tr,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: AppFonts.iosevkaCharon,
                        fontSize: widget.compact ? 22 : 30,
                        letterSpacing: widget.compact ? 3 : 5,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'v${AppStrings.currentAppVersion}',
                key: const Key('app-version-label'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: brandTheme.brandGold,
                  fontSize: widget.compact ? 11 : 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BoardTile extends StatelessWidget {
  const _BoardTile({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: const _BoardTilePainter()),
    );
  }
}

class _BoardTilePainter extends CustomPainter {
  const _BoardTilePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 2;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.12),
    );

    canvas.save();
    canvas.clipRRect(rrect);
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 2; col++) {
        canvas.drawRect(
          Rect.fromLTWH(col * cell, row * cell, cell, cell),
          Paint()
            ..color = (row + col).isOdd
                ? AppColors.boardDark
                : AppColors.boardLight,
        );
      }
    }

    void drawPiece(Offset center, Color fill, Color edge) {
      canvas.drawCircle(
        center + Offset(0, cell * 0.05),
        cell * 0.34,
        Paint()..color = Colors.black.withValues(alpha: 0.35),
      );
      canvas.drawCircle(center, cell * 0.34, Paint()..color = fill);
      canvas.drawCircle(
        center,
        cell * 0.34,
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.06,
      );
      canvas.drawCircle(
        center,
        cell * 0.2,
        Paint()
          ..color = edge.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.035,
      );
    }

    drawPiece(
      Offset(cell * 0.5, cell * 1.5),
      AppColors.pieceLight,
      AppColors.pieceLightEdge,
    );
    drawPiece(
      Offset(cell * 1.5, cell * 0.5),
      AppColors.pieceDark,
      AppColors.pieceDarkEdge,
    );
    canvas.restore();

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.03,
    );
  }

  @override
  bool shouldRepaint(covariant _BoardTilePainter oldDelegate) => false;
}
