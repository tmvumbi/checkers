import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../data/models/tournament.dart';
import '../../../../themes/app_theme.dart';
import '../../../../translations/translation_keys.dart';

/// Winners' podium: three pedestal cylinders (winner in the middle on the
/// tallest one), each topped by the player's photo and nickname, with the
/// position written on the cylinder face.
class TournamentPodium extends StatelessWidget {
  const TournamentPodium({required this.detail, super.key});

  final TournamentDetail detail;

  TournamentPlayer? _byRank(int rank) => detail.players
      .where((p) => p.finalRank == rank)
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;
    final first = _byRank(1);
    final second = _byRank(2);
    final third = _byRank(3);

    return Container(
      key: const Key('tournament-podium'),
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 0),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: second == null
                ? const SizedBox.shrink()
                : _PodiumColumn(
                    player: second,
                    label: TranslationKeys.podiumSecondShort.tr,
                    cylinderHeight: 58,
                    avatarRadius: 27,
                    topColor: const Color(0xFFE4E9EF),
                    sideColor: const Color(0xFF9AA3AE),
                    darkColor: const Color(0xFF6E7681),
                  ),
          ),
          Expanded(
            child: first == null
                ? const SizedBox.shrink()
                : _PodiumColumn(
                    player: first,
                    label: TranslationKeys.podiumFirstShort.tr,
                    cylinderHeight: 84,
                    avatarRadius: 33,
                    topColor: const Color(0xFFFFDF66),
                    sideColor: const Color(0xFFF0B400),
                    darkColor: const Color(0xFFA97B00),
                    crowned: true,
                  ),
          ),
          Expanded(
            child: third == null
                ? const SizedBox.shrink()
                : _PodiumColumn(
                    player: third,
                    label: TranslationKeys.podiumThirdShort.tr,
                    cylinderHeight: 44,
                    avatarRadius: 25,
                    topColor: const Color(0xFFE8B183),
                    sideColor: const Color(0xFFC77B3E),
                    darkColor: const Color(0xFF8C5524),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PodiumColumn extends StatelessWidget {
  const _PodiumColumn({
    required this.player,
    required this.label,
    required this.cylinderHeight,
    required this.avatarRadius,
    required this.topColor,
    required this.sideColor,
    required this.darkColor,
    this.crowned = false,
  });

  final TournamentPlayer player;
  final String label;
  final double cylinderHeight;
  final double avatarRadius;
  final Color topColor;
  final Color sideColor;
  final Color darkColor;
  final bool crowned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (crowned)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Icon(Icons.emoji_events, size: 22, color: topColor),
          ),
        Container(
          width: avatarRadius * 2,
          height: avatarRadius * 2,
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
        SizedBox(
          width: 92,
          height: cylinderHeight,
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
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  shadows: [
                    Shadow(
                      color: darkColor,
                      blurRadius: 4,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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
