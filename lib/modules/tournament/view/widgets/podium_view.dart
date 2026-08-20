import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../data/models/tournament.dart';
import '../../../../themes/app_theme.dart';
import '../../../../translations/translation_keys.dart';

const double _collapsedHeight = 64;
const double _expandedHeight = 234;

/// Winners' podium: three pedestal cylinders (winner in the middle on the
/// tallest one) topped by photo + nickname, position written on the
/// cylinder face. Collapsible: the winner's trophy, photo and nickname
/// animate into a compact champion strip; everything else sinks away.
class TournamentPodium extends StatefulWidget {
  const TournamentPodium({required this.detail, super.key});

  final TournamentDetail detail;

  @override
  State<TournamentPodium> createState() => _TournamentPodiumState();
}

class _TournamentPodiumState extends State<TournamentPodium>
    with TickerProviderStateMixin {
  // Starts collapsed: only the champion strip until the user expands.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 0,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );

  /// Slow sunburst rotation behind the pedestals.
  late final AnimationController _rays = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
  )..repeat();

  bool _expanded = false;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _rays.dispose();
    super.dispose();
  }

  TournamentPlayer? _byRank(int rank) =>
      widget.detail.players.where((p) => p.finalRank == rank).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;
    final first = _byRank(1);
    final second = _byRank(2);
    final third = _byRank(3);
    if (first == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final t = _t.value;
        return InkWell(
          key: const Key('tournament-podium-toggle'),
          onTap: _toggle,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            key: const Key('tournament-podium'),
            height: lerpDouble(_collapsedHeight, _expandedHeight, t),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  brand.brandGold.withValues(alpha: 0.14),
                  theme.colorScheme.shadow.withValues(alpha: 0.45),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: brand.brandGold.withValues(alpha: 0.8),
                width: 2,
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columnWidth = width / 3;
                return Stack(
                  children: [
                    // Rotating sunburst rays radiating from behind the
                    // champion (fades out while collapsing).
                    if (t > 0)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: 0.9 * t,
                            child: RepaintBoundary(
                              child: AnimatedBuilder(
                                animation: _rays,
                                builder: (context, _) => CustomPaint(
                                  painter: _RaysPainter(
                                    rotation: _rays.value * 2 * 3.14159265,
                                    color: brand.brandGold.withValues(
                                      alpha: 0.09,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Side pedestals + winner's cylinder sink and fade
                    // away while collapsing.
                    if (t > 0) ...[
                      if (second != null)
                        _sinking(
                          t,
                          left: 0,
                          width: columnWidth,
                          child: _SideColumn(
                            player: second,
                            label: TranslationKeys.podiumSecondShort.tr,
                            cylinderHeight: 58,
                            avatarRadius: 26,
                            topColor: const Color(0xFFE4E9EF),
                            sideColor: const Color(0xFF9AA3AE),
                            darkColor: const Color(0xFF6E7681),
                          ),
                        ),
                      if (third != null)
                        _sinking(
                          t,
                          left: columnWidth * 2,
                          width: columnWidth,
                          child: _SideColumn(
                            player: third,
                            label: TranslationKeys.podiumThirdShort.tr,
                            cylinderHeight: 44,
                            avatarRadius: 24,
                            topColor: const Color(0xFFE8B183),
                            sideColor: const Color(0xFFC77B3E),
                            darkColor: const Color(0xFF8C5524),
                          ),
                        ),
                      _sinking(
                        t,
                        left: columnWidth,
                        width: columnWidth,
                        child: _Cylinder(
                          label: TranslationKeys.podiumFirstShort.tr,
                          height: 84,
                          topColor: const Color(0xFFFFDF66),
                          sideColor: const Color(0xFFF0B400),
                          darkColor: const Color(0xFFA97B00),
                        ),
                      ),
                    ],
                    // The champion's trophy, photo and nickname travel
                    // between the strip and the pedestal top.
                    _winnerTrophy(t, width, brand),
                    _winnerAvatar(t, width, theme, first),
                    _winnerName(t, width, theme, brand, first),
                    // Chevron flips as the state changes.
                    Positioned(
                      right: 8,
                      top: lerpDouble(_collapsedHeight / 2 - 14, 6, t)!,
                      child: Transform.rotate(
                        angle: t * 3.14159,
                        child: Icon(
                          Icons.expand_more,
                          size: 26,
                          color: theme.colorScheme.onPrimary.withValues(
                            alpha: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Positioned _sinking(
    double t, {
    required double left,
    required double width,
    required Widget child,
  }) {
    return Positioned(
      left: left,
      bottom: lerpDouble(-46, 0, t)!,
      width: width,
      child: Opacity(
        opacity: t.clamp(0, 1),
        child: IgnorePointer(child: child),
      ),
    );
  }

  Positioned _winnerTrophy(
    double t,
    double width,
    CheckersThemeExtension brand,
  ) {
    final size = lerpDouble(20, 22, t)!;
    return Positioned(
      left: lerpDouble(14, width / 2 - size / 2, t),
      top: lerpDouble(_collapsedHeight / 2 - 10, 10, t),
      child: Icon(
        Icons.emoji_events,
        size: size,
        color: const Color(0xFFFFDF66),
      ),
    );
  }

  Positioned _winnerAvatar(
    double t,
    double width,
    ThemeData theme,
    TournamentPlayer first,
  ) {
    final radius = lerpDouble(20, 32, t)!;
    return Positioned(
      left: lerpDouble(44, width / 2 - radius, t),
      top: lerpDouble(_collapsedHeight / 2 - radius, 34, t),
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          color: theme.colorScheme.shadow.withValues(alpha: 0.5),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.5),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          image: first.photoUrl == null
              ? null
              : DecorationImage(
                  image: NetworkImage(first.photoUrl!),
                  fit: BoxFit.cover,
                ),
        ),
        child: first.photoUrl == null
            ? Icon(
                Icons.person,
                size: radius,
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.75),
              )
            : null,
      ),
    );
  }

  Positioned _winnerName(
    double t,
    double width,
    ThemeData theme,
    CheckersThemeExtension brand,
    TournamentPlayer first,
  ) {
    // From "next to the avatar" to "centered under the avatar".
    final boxWidth = lerpDouble(width - 130, width / 3, t)!;
    return Positioned(
      left: lerpDouble(92, width / 2 - boxWidth / 2, t),
      top: lerpDouble(_collapsedHeight / 2 - 10, 102, t),
      width: boxWidth,
      child: Align(
        alignment: Alignment.lerp(Alignment.centerLeft, Alignment.center, t)!,
        child: Text(
          first.nickname,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge!.copyWith(
            color: Color.lerp(brand.brandGold, theme.colorScheme.onPrimary, t),
            fontWeight: FontWeight.w800,
            fontSize: lerpDouble(15, 13, t),
          ),
        ),
      ),
    );
  }
}

/// Alternating light wedges radiating from behind the champion, like a
/// classic winners' sunburst backdrop.
class _RaysPainter extends CustomPainter {
  const _RaysPainter({required this.rotation, required this.color});

  final double rotation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const rayCount = 14;
    const step = 2 * 3.14159265 / rayCount;
    final center = Offset(size.width / 2, size.height * 0.42);
    final radius = size.width + size.height;
    final paint = Paint()..color = color;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var i = 0; i < rayCount; i++) {
      canvas.drawPath(
        Path()
          ..moveTo(center.dx, center.dy)
          ..arcTo(rect, rotation + i * step, step / 2, false)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter oldDelegate) =>
      oldDelegate.rotation != rotation || oldDelegate.color != color;
}

/// Non-animated pedestal column for 2nd and 3rd place.
class _SideColumn extends StatelessWidget {
  const _SideColumn({
    required this.player,
    required this.label,
    required this.cylinderHeight,
    required this.avatarRadius,
    required this.topColor,
    required this.sideColor,
    required this.darkColor,
  });

  final TournamentPlayer player;
  final String label;
  final double cylinderHeight;
  final double avatarRadius;
  final Color topColor;
  final Color sideColor;
  final Color darkColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: avatarRadius * 2,
          height: avatarRadius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            color: theme.colorScheme.shadow.withValues(alpha: 0.5),
            image: player.photoUrl == null
                ? null
                : DecorationImage(
                    image: NetworkImage(player.photoUrl!),
                    fit: BoxFit.cover,
                  ),
          ),
          child: player.photoUrl == null
              ? Icon(
                  Icons.person,
                  size: avatarRadius,
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.75),
                )
              : null,
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            player.nickname,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge!.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 4),
        _Cylinder(
          label: label,
          height: cylinderHeight,
          topColor: topColor,
          sideColor: sideColor,
          darkColor: darkColor,
        ),
      ],
    );
  }
}

class _Cylinder extends StatelessWidget {
  const _Cylinder({
    required this.label,
    required this.height,
    required this.topColor,
    required this.sideColor,
    required this.darkColor,
  });

  final String label;
  final double height;
  final Color topColor;
  final Color sideColor;
  final Color darkColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SizedBox(
        width: 92,
        height: height,
        child: CustomPaint(
          painter: _CylinderPainter(
            topColor: topColor,
            sideColor: sideColor,
            darkColor: darkColor,
          ),
          child: Align(
            alignment: const Alignment(0, 0.35),
            child: Text(
              label,
              style: theme.textTheme.bodyLarge!.copyWith(
                // Dark embossed text stays readable on the light
                // metallic center of every cylinder.
                color: Color.alphaBlend(
                  Colors.black.withValues(alpha: 0.62),
                  darkColor,
                ),
                fontWeight: FontWeight.w900,
                fontSize: 21,
                shadows: [
                  Shadow(
                    color: Colors.white.withValues(alpha: 0.45),
                    blurRadius: 0,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A simple 3D pedestal: elliptical cap + metallic-gradient body.
class _CylinderPainter extends CustomPainter {
  const _CylinderPainter({
    required this.topColor,
    required this.sideColor,
    required this.darkColor,
  });

  final Color topColor;
  final Color sideColor;
  final Color darkColor;

  @override
  void paint(Canvas canvas, Size size) {
    final capHeight = size.width * 0.24;

    final bodyRect = Rect.fromLTRB(0, capHeight / 2, size.width, size.height);
    canvas.drawRect(
      bodyRect,
      Paint()
        ..shader = LinearGradient(
          colors: [darkColor, sideColor, topColor, sideColor, darkColor],
          stops: const [0, 0.22, 0.5, 0.78, 1],
        ).createShader(bodyRect),
    );

    final capRect = Rect.fromLTWH(0, 0, size.width, capHeight);
    canvas.drawOval(capRect, Paint()..color = topColor);
    canvas.drawOval(
      capRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant _CylinderPainter oldDelegate) =>
      oldDelegate.topColor != topColor ||
      oldDelegate.sideColor != sideColor ||
      oldDelegate.darkColor != darkColor;
}
