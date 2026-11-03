import 'dart:math' as math;
import 'detection_config.dart';

/// A detection box in ORIGINAL frame pixels (not model-input pixels).
class Detection {
  final double l, t, r, b, conf;
  final int cls;
  const Detection(this.l, this.t, this.r, this.b, this.conf, this.cls);

  double get w => r - l;
  double get h => b - t;
  double get area => w * h;
  double get cx => (l + r) / 2;
  double get cy => (t + b) / 2;
  double get aspectRatio => h > 0 ? (w / h) : 0.0;
}

// -----------------------------------------------------------------------------
// IoU helper
// -----------------------------------------------------------------------------

double iou(Detection a, Detection b) {
  final iw = math.min(a.r, b.r) - math.max(a.l, b.l);
  final ih = math.min(a.b, b.b) - math.max(a.t, b.t);
  if (iw <= 0 || ih <= 0) return 0;
  final inter = iw * ih;
  final union = a.area + b.area - inter;
  return union <= 0 ? 0 : inter / union;
}

// -----------------------------------------------------------------------------
// Minimum-size filter & Outlier Validation
// -----------------------------------------------------------------------------

/// Returns true when the box meets the configured minimum dimensions.
/// All thresholds are in original-image pixels.
bool meetsMinSize(Detection d) {
  if (kMinBoxWidth > 0 && d.w < kMinBoxWidth) return false;
  if (kMinBoxHeight > 0 && d.h < kMinBoxHeight) return false;
  if (kMinBoxArea > 0 && d.area < kMinBoxArea) return false;
  return true;
}

/// Checks whether a proposed candidate box is geometrically valid.
/// Filters out extreme aspect-ratio artifacts (e.g. razor-thin or whole-screen
/// width hallucinations where w/h > 12 or h/w > 12).
bool isGeometricallyValid(Detection d, int frameW, int frameH) {
  if (d.w <= 0 || d.h <= 0) return false;
  // Discard boxes covering > 95% of the frame width AND height (usually full-screen false positive)
  if (d.w >= frameW * 0.95 && d.h >= frameH * 0.95) return false;
  // Discard extreme aspect ratios that don't match road depressions
  if (d.aspectRatio > 12.0 || (d.aspectRatio < 0.08 && d.h > 100)) return false;
  return true;
}

// -----------------------------------------------------------------------------
// Non-maximum suppression
// -----------------------------------------------------------------------------

/// Greedy per-class NMS.
/// [dets] must already be sorted descending by confidence before calling.
List<Detection> nms(
  List<Detection> dets, {
  double iouThr = kNmsIouThreshold,
  int maxOut = kMaxDetections,
}) {
  final keep = <Detection>[];
  for (final d in dets) {
    if (keep.length >= maxOut) break;
    final suppress = keep.any((k) => k.cls == d.cls && iou(k, d) > iouThr);
    if (!suppress) keep.add(d);
  }
  return keep;
}

// -----------------------------------------------------------------------------
// Letterbox maths
// -----------------------------------------------------------------------------

/// Resize-with-padding geometry for mapping model coords <-> original pixels.
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

  /// Model-input pixel -> original-image pixel.
  double origX(double x) => (x - padX) / scale;
  double origY(double y) => (y - padY) / scale;
}

// -----------------------------------------------------------------------------
// Severity rating
// -----------------------------------------------------------------------------

class Severity {
  final double score;
  final String label;
  const Severity(this.score, this.label);
}

/// 0-100 severity score from box area, vertical position, and confidence.
Severity rateSeverity(Detection d, int fw, int fh) {
  final area = (d.area / (fw * fh) / 0.15).clamp(0.0, 1.0);
  final pos = (d.b / fh).clamp(0.0, 1.0);
  var score = 100 * (0.65 * area + 0.2 * pos + 0.15 * d.conf);
  if (d.conf < 0.6) score = math.min(score, 69);
  final label = score > 70 ? 'Severe' : (score >= 35 ? 'Moderate' : 'Minor');
  return Severity(score, label);
}

// -----------------------------------------------------------------------------
// Direction guidance
// -----------------------------------------------------------------------------

enum Direction { left, centre, right, stop }

extension DirectionLabel on Direction {
  String get label => switch (this) {
        Direction.left => 'MOVE LEFT',
        Direction.centre => 'CONTINUE',
        Direction.right => 'MOVE RIGHT',
        Direction.stop => 'STOP / NO CLEAR DIRECTION',
      };

  String get voiceText => switch (this) {
        Direction.left => 'Move left.',
        Direction.centre => 'Continue ahead.',
        Direction.right => 'Move right.',
        Direction.stop => 'No clear direction. Stop.',
      };
}

class DirectionResult {
  final Direction recommendation;
  final int leftCount, centreCount, rightCount;
  final bool isPreliminary;

  const DirectionResult({
    required this.recommendation,
    required this.leftCount,
    required this.centreCount,
    required this.rightCount,
    this.isPreliminary = true,
  });
}

DirectionResult analyseDirection(List<Detection> dets, int fw) {
  if (fw <= 0) {
    return const DirectionResult(
      recommendation: Direction.stop,
      leftCount: 0,
      centreCount: 0,
      rightCount: 0,
    );
  }

  var lCount = 0, cCount = 0, rCount = 0;
  for (final d in dets) {
    final cx = d.cx / fw;
    if (cx < kLeftEdge) {
      lCount++;
    } else if (cx < kRightEdge) {
      cCount++;
    } else {
      rCount++;
    }
  }

  Direction rec;
  if (dets.isEmpty) {
    rec = Direction.centre;
  } else if (lCount == 0 && cCount == 0) {
    rec = (rCount > 0) ? Direction.centre : Direction.right;
  } else if (rCount == 0 && cCount == 0) {
    rec = (lCount > 0) ? Direction.centre : Direction.left;
  } else if (lCount == 0) {
    rec = Direction.left;
  } else if (rCount == 0) {
    rec = Direction.right;
  } else if (cCount == 0 && lCount > 0 && rCount > 0) {
    rec = Direction.centre;
  } else {
    rec = Direction.stop;
  }

  return DirectionResult(
    recommendation: rec,
    leftCount: lCount,
    centreCount: cCount,
    rightCount: rCount,
    isPreliminary: true,
  );
}

// -----------------------------------------------------------------------------
// TASK 6: Ground-Plane Perspective Physical Size Estimation
// -----------------------------------------------------------------------------

/// Estimated physical metric dimensions on the road plane.
class PhysicalSize {
  /// Estimated physical width in centimetres.
  final double widthCm;

  /// Estimated physical length/height on the road plane in centimetres.
  final double lengthCm;

  /// Estimated surface footprint area in square centimetres.
  final double areaCm2;

  /// Estimated longitudinal distance from camera to the pothole in centimetres.
  final double distanceCm;

  /// Whether camera geometry allows a valid road-plane projection.
  final bool isValid;

  const PhysicalSize({
    required this.widthCm,
    required this.lengthCm,
    required this.areaCm2,
    required this.distanceCm,
    required this.isValid,
  });

  static const invalid = PhysicalSize(
    widthCm: 0,
    lengthCm: 0,
    areaCm2: 0,
    distanceCm: 0,
    isValid: false,
  );
}

/// Perspective road-plane estimator using pinhole geometry and ground projection.
///
/// Under a flat road assumption:
/// - Camera is mounted at height `h` (cm) above road.
/// - Camera is tilted downward by pitch angle `theta` (radians).
/// - For a pixel at row `y` (where y=0 is top, y=frameH is bottom):
///     vertical ray angle phi = (0.5 - y / frameH) * fovV
///     ground distance Z = h / tan(theta + phi)
///     lateral scale factor (cm per pixel) at distance Z:
///         scaleX = 2 * Z * tan(fovH / 2) / frameW
///
/// NOTE: Pixels cannot directly be converted to centimetres without camera calibration
/// and ground-plane distance estimation. This model calculates distance-dependent
/// physical dimensions based on robot mounting geometry.
class GroundPlaneEstimator {
  final double cameraHeightCm;
  final double pitchDeg;
  final double fovHDeg;
  final double fovVDeg;

  const GroundPlaneEstimator({
    this.cameraHeightCm = kDefaultCameraHeightCm,
    this.pitchDeg = kDefaultCameraPitchDeg,
    this.fovHDeg = kDefaultCameraFovH,
    this.fovVDeg = kDefaultCameraFovV,
  });

  PhysicalSize estimate(Detection d, int frameW, int frameH) {
    if (frameW <= 0 || frameH <= 0 || d.w <= 0 || d.h <= 0) {
      return PhysicalSize.invalid;
    }

    final thetaRad = pitchDeg * (math.pi / 180.0);
    final fovVRad = fovVDeg * (math.pi / 180.0);
    final fovHRad = fovHDeg * (math.pi / 180.0);

    // Bottom edge of bounding box touches the road surface closest to robot
    final bottomNorm = d.b / frameH;

    // Angle of ray relative to camera optical axis (+ downwards, - upwards)
    final phiBottom = (bottomNorm - 0.5) * fovVRad;
    final totalAngle = thetaRad + phiBottom;

    // If ray points above horizon, it doesn't intersect road plane in front of robot
    if (totalAngle <= 0.05) {
      return PhysicalSize.invalid;
    }

    // Distance Z along the road plane from camera ground projection (cm)
    final distanceCm = cameraHeightCm / math.tan(totalAngle);
    if (distanceCm <= 0 || distanceCm > 1000) {
      return PhysicalSize.invalid;
    }

    // Width scale at that distance (cm per pixel)
    final sceneWidthCmAtZ = 2.0 * distanceCm * math.tan(fovHRad / 2.0);
    final cmPerPixelX = sceneWidthCmAtZ / frameW;

    // Projected ground length: calculate distance to top edge
    final topNorm = d.t / frameH;
    final phiTop = (topNorm - 0.5) * fovVRad;
    final totalAngleTop = thetaRad + phiTop;
    double lengthCm;
    if (totalAngleTop > 0.05) {
      final distanceTopCm = cameraHeightCm / math.tan(totalAngleTop);
      lengthCm = (distanceTopCm - distanceCm).abs();
    } else {
      // Fallback using foreshortening ratio
      lengthCm = (d.h * cmPerPixelX) / math.sin(totalAngle).clamp(0.2, 1.0);
    }

    final widthCm = d.w * cmPerPixelX;
    // Area approximated as ellipse or rectangle for surface footprint
    final areaCm2 = (math.pi / 4.0) * widthCm * lengthCm;

    return PhysicalSize(
      widthCm: widthCm.clamp(1.0, 500.0),
      lengthCm: lengthCm.clamp(1.0, 500.0),
      areaCm2: areaCm2.clamp(1.0, 250000.0),
      distanceCm: distanceCm,
      isValid: true,
    );
  }
}
