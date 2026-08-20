// Renders the launcher-icon source PNGs from the same drawing code as the
// play screen's CheckersLogoMark board tile.
//
// Run with:  flutter test tool/generate_app_icon_test.dart
// Then:      dart run flutter_launcher_icons
import 'dart:io';
import 'dart:ui' as ui;

import 'package:checkers/core/constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const double _canvasSize = 1024;

void _drawBoardTile(Canvas canvas, Rect rect) {
  final cell = rect.width / 2;
  final rrect = RRect.fromRectAndRadius(
    rect,
    Radius.circular(rect.width * 0.12),
  );

  canvas.save();
  canvas.clipRRect(rrect);
  for (var row = 0; row < 2; row++) {
    for (var col = 0; col < 2; col++) {
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left + col * cell,
          rect.top + row * cell,
          cell,
          cell,
        ),
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
    Offset(rect.left + cell * 0.5, rect.top + cell * 1.5),
    AppColors.pieceLight,
    AppColors.pieceLightEdge,
  );
  drawPiece(
    Offset(rect.left + cell * 1.5, rect.top + cell * 0.5),
    AppColors.pieceDark,
    AppColors.pieceDarkEdge,
  );
  canvas.restore();

  canvas.drawRRect(
    rrect,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.width * 0.03,
  );
}

void _drawFeltBackground(Canvas canvas, Rect rect) {
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.tableTop, AppColors.tableBottom],
      ).createShader(rect),
  );
}

Future<void> _savePng(
  String path,
  void Function(Canvas canvas, Rect rect) draw,
) async {
  final recorder = ui.PictureRecorder();
  const rect = Rect.fromLTWH(0, 0, _canvasSize, _canvasSize);
  draw(Canvas(recorder, rect), rect);
  final image = await recorder
      .endRecording()
      .toImage(_canvasSize.toInt(), _canvasSize.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  test('render launcher icon source images', () async {
    // Full-bleed icon (iOS + legacy Android): tile on the felt gradient.
    await _savePng('assets/icons/app_logo.png', (canvas, rect) {
      _drawFeltBackground(canvas, rect);
      final tileSize = rect.width * 0.72;
      _drawBoardTile(
        canvas,
        Rect.fromCenter(
          center: rect.center,
          width: tileSize,
          height: tileSize,
        ),
      );
    });

    // Android adaptive foreground: smaller tile, transparent backdrop
    // (the launcher masks ~2/3 of the canvas, so keep a safe margin).
    await _savePng('assets/icons/app_logo_foreground.png', (canvas, rect) {
      final tileSize = rect.width * 0.55;
      _drawBoardTile(
        canvas,
        Rect.fromCenter(
          center: rect.center,
          width: tileSize,
          height: tileSize,
        ),
      );
    });

    expect(File('assets/icons/app_logo.png').existsSync(), isTrue);
    expect(File('assets/icons/app_logo_foreground.png').existsSync(), isTrue);
  });
}
