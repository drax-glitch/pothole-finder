import 'dart:math' as math;

/// A box in ORIGINAL frame pixels.
class Detection {
  final double l, t, r, b, conf;
  final int cls;
  const Detection(this.l, this.t, this.r, this.b, this.conf, this.cls);
  double get w => r - l;
  double get h => b - t;
  double get area => w * h;
  double get cx => (l + r) / 2;
  double get cy => (t + b) / 2;
}

double iou(Detection a, Detection b) {
  final iw = math.min(a.r, b.r) - math.max(a.l, b.l);
  final ih = math.min(a.b, b.b) - math.max(a.t, b.t);
  if (iw <= 0 || ih <= 0) return 0;
  final inter = iw * ih;
  final union = a.area + b.area - inter;
  return union <= 0 ? 0 : inter / union;
}

/// Per-class non-maximum suppression.
List<Detection> nms(List<Detection> dets, {double iouThr = 0.45}) {
  final sorted = List<Detection>.from(dets)..sort((a, b) => b.conf.compareTo(a.conf));
  final keep = <Detection>[];
  for (final d in sorted) {
    if (keep.every((k) => k.cls != d.cls || iou(k, d) <= iouThr)) keep.add(d);
  }
  return keep;
}

/// Letterbox: resize keeping aspect ratio, centre, pad the rest.
class Letterbox {
  final double scale;
  final int newW, newH, padX, padY;
  const Letterbox(this.scale, this.newW, this.newH, this.padX, this.padY);

  factory Letterbox.of(int w, int h, int inW, int inH) {
    final s = math.min(inW / w, inH / h);
    final nw = (w * s).round().clamp(1, inW);
    final nh = (h * s).round().clamp(1, inH);
    return Letterbox(s, nw, nh, (inW - nw) ~/ 2, (inH - nh) ~/ 2);
  }

  /// Model-input pixel -> original image pixel.
  double origX(double x) => (x - padX) / scale;
  double origY(double y) => (y - padY) / scale;
}

class Severity {
  final double score;
  final String label;
  const Severity(this.score, this.label);
}

/// 0-100 score from box area, position in frame and confidence.
Severity rateSeverity(Detection d, int fw, int fh) {
  final area = (d.area / (fw * fh) / 0.15).clamp(0.0, 1.0);
  final pos = (d.b / fh).clamp(0.0, 1.0);
  var score = 100 * (0.65 * area + 0.2 * pos + 0.15 * d.conf);
  if (d.conf < 0.6) score = math.min(score, 69);
  final label = score > 70 ? 'Severe' : (score >= 35 ? 'Moderate' : 'Minor');
  return Severity(score, label);
}
