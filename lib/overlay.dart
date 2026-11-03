import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';
import 'vision_math.dart';

// -----------------------------------------------------------------------------
// DetBoxPainter - draws bounding boxes, labels, and physical measurements
// -----------------------------------------------------------------------------

class DetBoxPainter extends CustomPainter {
  final List<Detection> dets;
  final int fw, fh;
  final GroundPlaneEstimator estimator;
  final bool showPhysicalUnits;

  const DetBoxPainter(
    this.dets,
    this.fw,
    this.fh, {
    this.estimator = const GroundPlaneEstimator(),
    this.showPhysicalUnits = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fw == 0 || fh == 0 || dets.isEmpty) return;

    final s = math.min(size.width / fw, size.height / fh);
    final ox = (size.width - fw * s) / 2;
    final oy = (size.height - fh * s) / 2;

    for (var idx = 0; idx < dets.length; idx++) {
      final d = dets[idx];
      final sev = _severityOf(d.conf);
      final phys = estimator.estimate(d, fw, fh);
      _drawBox(canvas, d, s, ox, oy, sev, idx + 1, phys);
    }
  }

  void _drawBox(
    Canvas canvas,
    Detection d,
    double s,
    double ox,
    double oy,
    _Sev sev,
    int num,
    PhysicalSize phys,
  ) {
    final rect = Rect.fromLTRB(
      ox + d.l * s,
      oy + d.t * s,
      ox + d.r * s,
      oy + d.b * s,
    );

    // Subtle outer halo
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = sev.color.withAlpha(70),
    );

    // Primary crisp bounding box
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = sev.color,
    );

    // Primary Header Chip: "#N • XX% • Severity"
    final label = '#$num • ${(d.conf * 100).round()}% • ${sev.label}';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          shadows: [Shadow(blurRadius: 3, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    var top = rect.top - tp.height - 7;
    if (top < 0) top = rect.top + 3;

    final chipRect = Rect.fromLTWH(rect.left, top, tp.width + 10, tp.height + 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(chipRect, const Radius.circular(4)),
      Paint()..color = sev.color.withAlpha(230),
    );
    tp.paint(canvas, Offset(chipRect.left + 5, chipRect.top + 3));

    // Secondary Sub-Chip: Pixel dimensions & estimated physical metric size
    final dimText = phys.isValid && showPhysicalUnits
        ? '${d.w.round()}x${d.h.round()} px (~${phys.widthCm.toStringAsFixed(0)}x${phys.lengthCm.toStringAsFixed(0)} cm)'
        : '${d.w.round()}x${d.h.round()} px (${(d.area / 1000).toStringAsFixed(1)}k px²)';

    final tpDim = TextPainter(
      text: TextSpan(
        text: dimText,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 9.5,
          shadows: [Shadow(blurRadius: 2, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final dimBottom = rect.bottom + 2;
    if (dimBottom + tpDim.height + 4 <= (ox + fh * s + 50)) {
      final dimChip = Rect.fromLTWH(rect.left, dimBottom, tpDim.width + 8, tpDim.height + 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(dimChip, const Radius.circular(3)),
        Paint()..color = Colors.black.withAlpha(190),
      );
      tpDim.paint(canvas, Offset(dimChip.left + 4, dimChip.top + 2));
    }
  }

  @override
  bool shouldRepaint(DetBoxPainter old) =>
      old.dets != dets || old.fw != fw || old.fh != fh || old.showPhysicalUnits != showPhysicalUnits;
}

// -----------------------------------------------------------------------------
// Severity colour helpers
// -----------------------------------------------------------------------------

class _Sev {
  final Color color;
  final String label;
  const _Sev(this.color, this.label);
}

_Sev _severityOf(double conf) {
  if (conf >= 0.70) return const _Sev(C.warn, 'Severe');
  if (conf >= 0.45) return const _Sev(C.yellow, 'Moderate');
  return const _Sev(C.mint, 'Minor');
}

Color severityColor(String label) =>
    label == 'Severe' ? C.warn : (label == 'Moderate' ? C.yellow : C.mint);

// -----------------------------------------------------------------------------
// DirectionPanel - Direction recommendation widget
// -----------------------------------------------------------------------------

class DirectionPanel extends StatelessWidget {
  final DirectionResult dir;
  const DirectionPanel(this.dir, {super.key});

  @override
  Widget build(BuildContext context) {
    final rec = dir.recommendation;

    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.explore, size: 16, color: C.muted),
            const SizedBox(width: 6),
            const Text('Direction guidance',
                style: TextStyle(color: C.muted, fontSize: 12, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (dir.isPreliminary)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: C.yellow.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: C.yellow.withAlpha(80)),
                ),
                child: const Text('PRELIMINARY',
                    style: TextStyle(color: C.yellow, fontSize: 9, fontWeight: FontWeight.w800)),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _Region('LEFT', dir.leftCount, rec == Direction.left, C.mint)),
            const SizedBox(width: 4),
            Expanded(child: _Region('CENTER', dir.centreCount, rec == Direction.centre, C.mint)),
            const SizedBox(width: 4),
            Expanded(child: _Region('RIGHT', dir.rightCount, rec == Direction.right, C.mint)),
          ]),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: _recColor(rec).withAlpha(30),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _recColor(rec).withAlpha(120)),
            ),
            child: Column(children: [
              Icon(_recIcon(rec), color: _recColor(rec), size: 28),
              const SizedBox(height: 4),
              Text(
                rec.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _recColor(rec),
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ]),
          ),
          if (dir.isPreliminary) ...[
            const SizedBox(height: 6),
            const Text(
              'Based on pothole positions only. Road boundaries, obstacles, '
              'and road curvature are not evaluated.',
              style: TextStyle(color: C.muted, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Color _recColor(Direction d) => switch (d) {
        Direction.left => C.mint,
        Direction.centre => C.mint,
        Direction.right => C.mint,
        Direction.stop => C.warn,
      };

  IconData _recIcon(Direction d) => switch (d) {
        Direction.left => Icons.arrow_back,
        Direction.centre => Icons.arrow_upward,
        Direction.right => Icons.arrow_forward,
        Direction.stop => Icons.block,
      };
}

class _Region extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final Color highlightColor;
  const _Region(this.label, this.count, this.isSelected, this.highlightColor);

  @override
  Widget build(BuildContext context) {
    final hasPothole = count > 0;
    final border = isSelected
        ? Border.all(color: highlightColor, width: 2)
        : Border.all(color: C.line);
    final bg = hasPothole
        ? C.warn.withAlpha(30)
        : (isSelected ? highlightColor.withAlpha(20) : C.asphalt);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: border,
      ),
      child: Column(children: [
        Text(label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: C.muted)),
        const SizedBox(height: 3),
        if (hasPothole)
          const Icon(Icons.warning_amber_rounded, color: C.warn, size: 16)
        else
          const Icon(Icons.check_circle_outline, color: C.mint, size: 16),
        Text(
          count == 0 ? 'Clear' : '$count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: hasPothole ? C.warn : C.mint,
          ),
        ),
      ]),
    );
  }
}

// -----------------------------------------------------------------------------
// DetectionLogPanel - diagnostic counts panel
// -----------------------------------------------------------------------------

class DetectionLogPanel extends StatelessWidget {
  final int candidates;
  final int afterNms;
  final int finalCount;
  const DetectionLogPanel({
    super.key,
    required this.candidates,
    required this.afterNms,
    required this.finalCount,
  });

  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Detection Pipeline Diagnostics',
              style: TextStyle(color: C.muted, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          _row('Raw candidates (above conf):', '$candidates'),
          _row('Retained after NMS:', '$afterNms'),
          _row('After min-size & geometry filter:', '$finalCount'),
        ]),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [
          Expanded(
              child: Text(label, style: const TextStyle(color: C.muted, fontSize: 11))),
          Text(value,
              style: const TextStyle(
                  color: C.text, fontSize: 11, fontWeight: FontWeight.w800)),
        ]),
      );
}
