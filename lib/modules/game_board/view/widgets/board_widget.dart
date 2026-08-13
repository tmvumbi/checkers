import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../engine/board_geometry.dart';
import '../../../../engine/checkers_engine.dart';
import '../../controller/game_board_controller.dart';

/// The interactive checkers board: squares, highlights, pieces, and
/// multi-hop move animation.
class BoardWidget extends GetView<GameBoardController> {
  const BoardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boardSide = constraints.biggest.shortestSide;
          return Obx(() {
            // Touch both observables so any board change rebuilds.
            controller.boardVersion.value;
            final selected = controller.selectedSquare.value;
            final animation = controller.activeAnimation.value;
            return GestureDetector(
              onTapUp: (details) =>
                  _handleTap(details.localPosition, boardSide),
              child: _BoardStack(
                boardSide: boardSide,
                selected: selected,
                animation: animation,
              ),
            );
          });
        },
      ),
    );
  }

  void _handleTap(Offset position, double boardSide) {
    final engine = controller.engine;
    final size = engine.config.boardSize;
    final cell = boardSide / size;
    var col = (position.dx / cell).floor().clamp(0, size - 1);
    var row = (position.dy / cell).floor().clamp(0, size - 1);
    if (controller.humanColor == PieceColor.black) {
      row = size - 1 - row;
      col = size - 1 - col;
    }
    final square = engine.geometry.indexOf(row, col);
    if (square != null) {
      controller.onSquareTapped(square);
    }
  }
}

class _BoardStack extends GetView<GameBoardController> {
  const _BoardStack({
    required this.boardSide,
    required this.selected,
    required this.animation,
  });

  final double boardSide;
  final int? selected;
  final PieceAnimation? animation;

  @override
  Widget build(BuildContext context) {
    final engine = controller.engine;
    final size = engine.config.boardSize;
    final cell = boardSide / size;

    Offset squareOffset(int square) {
      var row = engine.geometry.rowOf(square);
      var col = engine.geometry.colOf(square);
      if (controller.humanColor == PieceColor.black) {
        row = size - 1 - row;
        col = size - 1 - col;
      }
      return Offset(col * cell, row * cell);
    }

    final destinationSquares = <int>{};
    final threatenedSquares = <int>{};
    if (selected != null) {
      for (final move in controller.movesFrom(selected!)) {
        destinationSquares.add(move.to);
        threatenedSquares.addAll(move.captured);
      }
    }

    final lastMove = engine.moveHistory.isEmpty ? null : engine.moveHistory.last;
    final animatingMove = animation?.move;

    final pieces = <Widget>[];
    for (var square = 0; square < engine.config.squareCount; square++) {
      final color = engine.colorAt(square);
      if (color == null) {
        continue;
      }
      if (animatingMove != null && square == animatingMove.from) {
        continue; // Drawn by the animated overlay instead.
      }
      final isCapturedInAnimation =
          animatingMove?.captured.contains(square) ?? false;
      pieces.add(
        Positioned(
          left: squareOffset(square).dx,
          top: squareOffset(square).dy,
          width: cell,
          height: cell,
          child: Opacity(
            opacity: isCapturedInAnimation ? 0.55 : 1,
            child: PieceWidget(
              color: color,
              isKing: engine.isKingAt(square),
              highlighted: threatenedSquares.contains(square),
            ),
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CustomPaint(
          size: Size.square(boardSide),
          painter: _BoardPainter(
            boardSize: size,
            darkSquares: {
              for (var s = 0; s < engine.config.squareCount; s++)
                squareOffset(s),
            },
            selectedOffset: selected == null ? null : squareOffset(selected!),
            destinationOffsets: {
              for (final s in destinationSquares) squareOffset(s),
            },
            lastMoveOffsets: lastMove == null || animatingMove != null
                ? const {}
                : {squareOffset(lastMove.from), squareOffset(lastMove.to)},
            cell: cell,
          ),
        ),
        ...pieces,
        if (animatingMove != null)
          _AnimatedPiece(
            key: ValueKey(
              'anim-${animatingMove.from}-${animatingMove.to}-'
              '${engine.moveHistory.length}',
            ),
            waypoints: [
              squareOffset(animatingMove.from),
              for (final p in animatingMove.path) squareOffset(p),
            ],
            cell: cell,
            color: engine.colorAt(animatingMove.from)!,
            isKing: engine.isKingAt(animatingMove.from),
          ),
      ],
    );
  }
}

class _BoardPainter extends CustomPainter {
  const _BoardPainter({
    required this.boardSize,
    required this.darkSquares,
    required this.selectedOffset,
    required this.destinationOffsets,
    required this.lastMoveOffsets,
    required this.cell,
  });

  final int boardSize;
  final Set<Offset> darkSquares;
  final Offset? selectedOffset;
  final Set<Offset> destinationOffsets;
  final Set<Offset> lastMoveOffsets;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()..color = AppColors.boardLight;
    final dark = Paint()..color = AppColors.boardDark;
    canvas.drawRect(Offset.zero & size, light);
    for (final offset in darkSquares) {
      canvas.drawRect(offset & Size.square(cell), dark);
    }
    for (final offset in lastMoveOffsets) {
      canvas.drawRect(
        offset & Size.square(cell),
        Paint()..color = AppColors.lastMoveTint,
      );
    }
    if (selectedOffset != null) {
      canvas.drawRect(
        (selectedOffset! & Size.square(cell)).deflate(1.5),
        Paint()
          ..color = AppColors.gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    for (final offset in destinationOffsets) {
      canvas.drawCircle(
        offset + Offset(cell / 2, cell / 2),
        cell * 0.16,
        Paint()..color = AppColors.moveHighlight,
      );
      canvas.drawCircle(
        offset + Offset(cell / 2, cell / 2),
        cell * 0.16,
        Paint()
          ..color = AppColors.gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    // Frame.
    canvas.drawRect(
      (Offset.zero & size).deflate(1),
      Paint()
        ..color = AppColors.boardFrame
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) {
    return oldDelegate.selectedOffset != selectedOffset ||
        oldDelegate.destinationOffsets.length !=
            destinationOffsets.length ||
        oldDelegate.lastMoveOffsets.length != lastMoveOffsets.length ||
        oldDelegate.cell != cell;
  }
}

class PieceWidget extends StatelessWidget {
  const PieceWidget({
    required this.color,
    required this.isKing,
    this.highlighted = false,
    super.key,
  });

  final PieceColor color;
  final bool isKing;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PiecePainter(
        color: color,
        isKing: isKing,
        highlighted: highlighted,
      ),
    );
  }
}

class _PiecePainter extends CustomPainter {
  const _PiecePainter({
    required this.color,
    required this.isKing,
    required this.highlighted,
  });

  final PieceColor color;
  final bool isKing;
  final bool highlighted;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.38;
    final fill =
        color == PieceColor.white ? AppColors.pieceLight : AppColors.pieceDark;
    final edge = color == PieceColor.white
        ? AppColors.pieceLightEdge
        : AppColors.pieceDarkEdge;

    canvas.drawCircle(
      center + Offset(0, radius * 0.12),
      radius,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawCircle(center, radius, Paint()..color = fill);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = highlighted ? AppColors.captureHighlight : edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.14,
    );
    canvas.drawCircle(
      center,
      radius * 0.6,
      Paint()
        ..color = edge.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.07,
    );
    if (isKing) {
      final crown = Paint()..color = AppColors.gold;
      canvas.drawCircle(center, radius * 0.3, crown);
      canvas.drawCircle(
        center,
        radius * 0.3,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PiecePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.isKing != isKing ||
        oldDelegate.highlighted != highlighted;
  }
}

/// Slides a piece through its waypoints, one 180ms hop per segment —
/// timing mirrors GameBoardController._animateAndApply.
class _AnimatedPiece extends StatefulWidget {
  const _AnimatedPiece({
    required this.waypoints,
    required this.cell,
    required this.color,
    required this.isKing,
    super.key,
  });

  final List<Offset> waypoints;
  final double cell;
  final PieceColor color;
  final bool isKing;

  @override
  State<_AnimatedPiece> createState() => _AnimatedPieceState();
}

class _AnimatedPieceState extends State<_AnimatedPiece>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _position;

  @override
  void initState() {
    super.initState();
    final segments = widget.waypoints.length - 1;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 180 * segments),
    );
    _position = TweenSequence<Offset>([
      for (var i = 0; i < segments; i++)
        TweenSequenceItem(
          tween: Tween(
            begin: widget.waypoints[i],
            end: widget.waypoints[i + 1],
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 1,
        ),
    ]).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _position,
      builder: (context, child) {
        return Positioned(
          left: _position.value.dx,
          top: _position.value.dy,
          width: widget.cell,
          height: widget.cell,
          child: child!,
        );
      },
      child: PieceWidget(color: widget.color, isKing: widget.isKing),
    );
  }
}

// Keep an explicit dependency on BoardGeometry so the import is meaningful
// for readers; the geometry itself is reached through the engine.
typedef BoardGeometryRef = BoardGeometry;
