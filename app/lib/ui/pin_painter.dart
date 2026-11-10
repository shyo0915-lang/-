import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'format.dart';

class PinGlyphPainter extends CustomPainter {
  PinGlyphPainter({required this.fill, required this.shape, this.selected = false});

  final Color fill;
  final String shape;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide * 0.34;
    final tip = Offset(size.width / 2, size.height - 1);
    final center = Offset(tip.dx, tip.dy - radius * 1.75);
    final reach = radius * 0.72;
    final arcY = center.dy + radius * 0.69;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - reach, arcY)
      ..arcToPoint(Offset(tip.dx + reach, arcY), radius: Radius.circular(radius), largeArc: true)
      ..close();
    if (selected) {
      canvas.drawCircle(center, radius + 5, Paint()..color = const Color(0xFF151515)..style = PaintingStyle.stroke..strokeWidth = 3);
    }
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _glyph(canvas, center, radius, inkFor(fill), shape);
  }

  @override
  bool shouldRepaint(PinGlyphPainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.shape != shape || oldDelegate.selected != selected;
}

void _glyph(Canvas canvas, Offset center, double radius, Color ink, String shape) {
  final paint = Paint()
    ..color = ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.6, radius * 0.22)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  switch (shape) {
    case 'diamond':
      final k = radius * 0.48;
      canvas.drawPath(
        Path()
          ..moveTo(center.dx, center.dy - k)
          ..lineTo(center.dx + k, center.dy)
          ..lineTo(center.dx, center.dy + k)
          ..lineTo(center.dx - k, center.dy)
          ..close(),
        Paint()..color = ink,
      );
    case 'ring':
      canvas.drawCircle(center, radius * 0.36, paint);
    case 'cross':
      final k = radius * 0.36;
      canvas.drawLine(center.translate(-k, -k), center.translate(k, k), paint);
      canvas.drawLine(center.translate(k, -k), center.translate(-k, k), paint);
    case 'star':
      final path = Path();
      for (var i = 0; i < 5; i++) {
        final angle = -math.pi / 2 + i * 4 * math.pi / 5;
        final point = center + Offset(math.cos(angle), math.sin(angle)) * radius * 0.48;
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, Paint()..color = ink);
    case 'square':
      final k = radius * 0.34;
      canvas.drawRect(Rect.fromCenter(center: center, width: k * 2, height: k * 2), paint);
    case 'check':
    default:
      final path = Path()
        ..moveTo(center.dx - radius * 0.45, center.dy)
        ..lineTo(center.dx - radius * 0.1, center.dy + radius * 0.36)
        ..lineTo(center.dx + radius * 0.48, center.dy - radius * 0.34);
      canvas.drawPath(path, paint);
  }
}

Future<ui.Image> pinImage({required Color fill, required String shape, required double diameter, bool selected = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(diameter, diameter * 1.35);
  PinGlyphPainter(fill: fill, shape: shape, selected: selected).paint(canvas, size);
  final picture = recorder.endRecording();
  return picture.toImage(size.width.ceil(), size.height.ceil());
}
