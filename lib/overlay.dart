import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';
import 'vision_math.dart';

/// Draws boxes over an image shown with BoxFit.contain in the same bounds.
/// Frame pixels -> screen pixels uses the real contain offset and scale.
class DetBoxPainter extends CustomPainter {
  final List<Detection> dets;
  final int fw, fh;
  const DetBoxPainter(this.dets, this.fw, this.fh);

  @override
  void paint(Canvas canvas, Size size) {
    if (fw == 0 || fh == 0) return;
    final s = math.min(size.width / fw, size.height / fh);
    final ox = (size.width - fw * s) / 2, oy = (size.height - fh * s) / 2;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = C.mint;
    for (final d in dets) {
      final rect = Rect.fromLTRB(ox + d.l * s, oy + d.t * s, ox + d.r * s, oy + d.b * s);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), stroke);
      final tp = TextPainter(
        text: TextSpan(
          text: 'Pothole ${(d.conf * 100).round()}%',
          style: const TextStyle(color: C.asphalt, fontWeight: FontWeight.w800, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      var top = rect.top - tp.height - 6;
      if (top < 0) top = rect.top;
      final chip = Rect.fromLTWH(rect.left, top, tp.width + 10, tp.height + 6);
      canvas.drawRRect(RRect.fromRectAndRadius(chip, const Radius.circular(4)), Paint()..color = C.mint);
      tp.paint(canvas, Offset(chip.left + 5, chip.top + 3));
    }
  }

  @override
  bool shouldRepaint(DetBoxPainter old) => old.dets != dets || old.fw != fw || old.fh != fh;
}

Color severityColor(String label) =>
    label == 'Severe' ? C.warn : (label == 'Moderate' ? C.yellow : C.mint);
