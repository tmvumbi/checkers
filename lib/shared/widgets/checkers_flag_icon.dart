import 'package:flutter/material.dart';

enum CheckersFlagKind { english, french }

class CheckersFlagIcon extends StatelessWidget {
  const CheckersFlagIcon({
    required this.kind,
    super.key,
    this.size = const Size(26, 18),
  });

  final CheckersFlagKind kind;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _CheckersFlagPainter(kind), size: size);
  }
}

class _CheckersFlagPainter extends CustomPainter {
  const _CheckersFlagPainter(this.kind);

  final CheckersFlagKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(size.height * 0.14);
    final rrect = RRect.fromRectAndRadius(rect, radius);

    canvas.save();
    canvas.clipRRect(rrect);

    switch (kind) {
      case CheckersFlagKind.english:
        _paintUnionFlag(canvas, size);
      case CheckersFlagKind.french:
        _paintFrenchFlag(canvas, size);
    }

    canvas.restore();

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.78)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  void _paintUnionFlag(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF1F4EA3));

    final whiteDiagonal = Paint()
      ..color = Colors.white
      ..strokeWidth = size.height * 0.38
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset.zero,
      Offset(size.width, size.height),
      whiteDiagonal,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(0, size.height),
      whiteDiagonal,
    );

    final redDiagonal = Paint()
      ..color = const Color(0xFFC8102E)
      ..strokeWidth = size.height * 0.18
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), redDiagonal);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), redDiagonal);

    canvas.drawRect(
      Rect.fromCenter(
        center: rect.center,
        width: size.width,
        height: size.height * 0.42,
      ),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: rect.center,
        width: size.width * 0.34,
        height: size.height,
      ),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: rect.center,
        width: size.width,
        height: size.height * 0.22,
      ),
      Paint()..color = const Color(0xFFC8102E),
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: rect.center,
        width: size.width * 0.18,
        height: size.height,
      ),
      Paint()..color = const Color(0xFFC8102E),
    );
  }

  void _paintFrenchFlag(Canvas canvas, Size size) {
    final stripeWidth = size.width / 3;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, stripeWidth, size.height),
      Paint()..color = const Color(0xFF1B4EA3),
    );
    canvas.drawRect(
      Rect.fromLTWH(stripeWidth, 0, stripeWidth, size.height),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromLTWH(stripeWidth * 2, 0, stripeWidth, size.height),
      Paint()..color = const Color(0xFFE3343F),
    );
  }

  @override
  bool shouldRepaint(covariant _CheckersFlagPainter oldDelegate) {
    return oldDelegate.kind != kind;
  }
}
