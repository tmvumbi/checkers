import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/models/tournament.dart';
import '../../../../shared/tournament_display.dart';
import '../../../../themes/app_theme.dart';
import '../../../../translations/translation_keys.dart';
import '../../controller/tournament_controller.dart';

const double _cardWidth = 208;
const double _cardHeight = 118;
const double _columnGap = 44;
const double _rowGap = 18;
const double _thirdPlaceGap = 26;

/// World-cup style bracket: one column per stage, match cards with stage
/// banner + "Match N" footer, elbow connectors into the next round, and
/// the third-place match tucked under the final.
class TournamentBracket extends GetView<TournamentController> {
  const TournamentBracket({required this.detail, super.key});

  final TournamentDetail detail;

  @override
  Widget build(BuildContext context) {
    final layout = _BracketLayout.compute(detail);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: SingleChildScrollView(
        child: SizedBox(
          width: layout.size.width,
          height: layout.size.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ConnectorPainter(
                    connectors: layout.connectors,
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withValues(alpha: 0.45),
                  ),
                ),
              ),
              for (final placed in layout.cards)
                Positioned(
                  left: placed.offset.dx,
                  top: placed.offset.dy,
                  width: _cardWidth,
                  height: _cardHeight,
                  child: _BracketMatchCard(
                    detail: detail,
                    match: placed.match,
                    matchNumber: placed.number,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlacedMatch {
  _PlacedMatch(this.match, this.offset, this.number);

  final TournamentMatch match;
  final Offset offset;
  final int number;
}

class _BracketLayout {
  _BracketLayout(this.cards, this.connectors, this.size);

  final List<_PlacedMatch> cards;
  final List<(Offset, Offset)> connectors;
  final Size size;

  static _BracketLayout compute(TournamentDetail detail) {
    final stages =
        detail.matches
            .map((m) => m.stage)
            .where((s) => s != 'third')
            .toSet()
            .toList()
          ..sort(
            (a, b) =>
                tournamentStageOrder(a).compareTo(tournamentStageOrder(b)),
          );

    final cards = <_PlacedMatch>[];
    final connectors = <(Offset, Offset)>[];
    final centers = <String, Offset>{}; // match id -> card center
    var number = 1;
    var maxBottom = 0.0;

    for (final (column, stage) in stages.indexed) {
      final x = column * (_cardWidth + _columnGap);
      final stageMatches =
          detail.matches.where((m) => m.stage == stage).toList()
            ..sort((a, b) => a.matchIndex.compareTo(b.matchIndex));
      final previousStage = column == 0 ? null : stages[column - 1];

      for (final (row, match) in stageMatches.indexed) {
        // Center between the two feeder matches when they are known
        // (each player came from exactly one previous-stage match).
        double y;
        final feederCenters = <Offset>[];
        if (previousStage != null) {
          for (final uid in [match.p1Uid, match.p2Uid]) {
            final feeder = detail.matches
                .where(
                  (m) =>
                      m.stage == previousStage &&
                      (m.p1Uid == uid || m.p2Uid == uid),
                )
                .toList();
            final center = feeder.isEmpty ? null : centers[feeder.first.id];
            if (center != null && !feederCenters.contains(center)) {
              feederCenters.add(center);
            }
          }
        }
        if (feederCenters.isNotEmpty) {
          y =
              feederCenters
                  .map((c) => c.dy)
                  .reduce((a, b) => a + b) /
                  feederCenters.length -
              _cardHeight / 2;
        } else {
          y = row * (_cardHeight + _rowGap);
        }
        // Never overlap an earlier card in the same column.
        final minY = cards
            .where((p) => p.offset.dx == x)
            .fold<double>(0, (acc, p) => p.offset.dy + _cardHeight + _rowGap);
        if (y < minY && row > 0) {
          y = minY;
        }

        final offset = Offset(x, y);
        cards.add(_PlacedMatch(match, offset, number++));
        final center = Offset(x + _cardWidth / 2, y + _cardHeight / 2);
        centers[match.id] = center;
        for (final feederCenter in feederCenters) {
          connectors.add((
            Offset(feederCenter.dx + _cardWidth / 2, feederCenter.dy),
            Offset(x, center.dy),
          ));
        }
        maxBottom = maxBottom > y + _cardHeight ? maxBottom : y + _cardHeight;
      }
    }

    // Third-place match sits under the final.
    final third = detail.matches.where((m) => m.stage == 'third').toList();
    if (third.isNotEmpty) {
      final finalCard = cards
          .where((p) => p.match.stage == 'f')
          .toList();
      final x = finalCard.isEmpty
          ? stages.length * (_cardWidth + _columnGap)
          : finalCard.first.offset.dx;
      final y = finalCard.isEmpty
          ? 0.0
          : finalCard.first.offset.dy + _cardHeight + _thirdPlaceGap;
      cards.add(_PlacedMatch(third.first, Offset(x, y), number++));
      maxBottom = maxBottom > y + _cardHeight ? maxBottom : y + _cardHeight;
    }

    final width = stages.isEmpty
        ? _cardWidth
        : stages.length * (_cardWidth + _columnGap) - _columnGap;
    return _BracketLayout(cards, connectors, Size(width, maxBottom + 4));
  }
}

class _ConnectorPainter extends CustomPainter {
  const _ConnectorPainter({required this.connectors, required this.color});

  final List<(Offset, Offset)> connectors;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final (from, to) in connectors) {
      final midX = from.dx + (_columnGap / 2);
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..lineTo(midX, from.dy)
        ..lineTo(midX, to.dy)
        ..lineTo(to.dx, to.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectorPainter oldDelegate) =>
      oldDelegate.connectors != connectors || oldDelegate.color != color;
}

class _BracketMatchCard extends GetView<TournamentController> {
  const _BracketMatchCard({
    required this.detail,
    required this.match,
    required this.matchNumber,
  });

  final TournamentDetail detail;
  final TournamentMatch match;
  final int matchNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;

    Widget playerRow(String uid) {
      final player = controller.playerOf(uid);
      final isWinner = match.winnerUid == uid;
      final isLoser = match.isFinished && !isWinner;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isWinner
                      ? brand.brandGold
                      : theme.colorScheme.onPrimary.withValues(alpha: 0.55),
                  width: 1.5,
                ),
                image: player?.photoUrl == null
                    ? null
                    : DecorationImage(
                        image: NetworkImage(player!.photoUrl!),
                        fit: BoxFit.cover,
                      ),
              ),
              child: player?.photoUrl == null
                  ? Icon(
                      Icons.person,
                      size: 12,
                      color: theme.colorScheme.onPrimary.withValues(
                        alpha: 0.7,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                player?.nickname ?? '?',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge!.copyWith(
                  color: isWinner
                      ? brand.brandGold
                      : theme.colorScheme.onPrimary.withValues(
                          alpha: isLoser ? 0.55 : 1,
                        ),
                  fontWeight: isWinner ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
            if (isWinner)
              Icon(Icons.emoji_events, size: 14, color: brand.brandGold),
          ],
        ),
      );
    }

    return InkWell(
      key: Key('match-${match.id}'),
      onTap: () => controller.openMatch(match),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.shadow.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.onPrimary.withValues(alpha: 0.55),
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Stage banner (gold, like the classic bracket headers).
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.gold, Color(0xFFD99C00)],
                ),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(7),
                ),
              ),
              child: Text(
                tournamentStageLabel(match.stage).toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge!.copyWith(
                  color: AppColors.darkBlue,
                  fontWeight: FontWeight.w900,
                  fontSize: 11.5,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [playerRow(match.p1Uid), playerRow(match.p2Uid)],
              ),
            ),
            // "Match N" footer bar; pulses red while live.
            Container(
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.purple, AppColors.darkPurple],
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(7),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!match.isFinished) ...[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.redAccent,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    match.isFinished
                        ? TranslationKeys.tournamentMatchNumber.trParams({
                            'number': '$matchNumber',
                          })
                        : TranslationKeys.tournamentLive.tr,
                    style: theme.textTheme.bodyLarge!.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
