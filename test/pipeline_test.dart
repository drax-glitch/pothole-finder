import 'package:flutter_test/flutter_test.dart';
import 'package:potfinder/mjpeg.dart';
import 'package:potfinder/vision_math.dart';

void main() {
  test('MJPEG splitter finds frames across chunks', () {
    final sp = MjpegSplitter();
    final frames = <List<int>>[];
    sp.add([0x00, 0xFF, 0xD8, 0x01, 0x02], frames.add);
    expect(frames, isEmpty);
    sp.add([0x03, 0xFF, 0xD9, 0x00], frames.add);
    expect(frames.length, 1);
    expect(frames.first, [0xFF, 0xD8, 0x01, 0x02, 0x03, 0xFF, 0xD9]);
  });

  test('Letterbox 640x480 into 640x640 coordinate transform', () {
    final lb = Letterbox.of(640, 480, 640, 640);
    expect(lb.scale, 1.0);
    expect(lb.padY, 80);
    expect(lb.padX, 0);
    expect(lb.origY(80), 0);
    expect(lb.origY(560), 480);
  });

  test('NMS suppresses duplicate/overlapping proposals on same pothole', () {
    const a1 = Detection(100, 100, 200, 200, 0.90, 0);
    const a2 = Detection(105, 102, 204, 198, 0.78, 0);
    const b = Detection(400, 300, 500, 400, 0.85, 0);

    final kept = nms([a1, a2, b]);
    expect(kept.length, 2);
    expect(kept[0], a1);
    expect(kept[1], b);
  });

  test('Multiple distinct potholes are all preserved simultaneously', () {
    const p1 = Detection(20, 200, 120, 300, 0.88, 0);
    const p2 = Detection(250, 220, 350, 320, 0.82, 0);
    const p3 = Detection(480, 210, 580, 310, 0.79, 0);

    final kept = nms([p1, p2, p3]);
    expect(kept.length, 3);
  });

  test('Outlier and extreme aspect-ratio filtering prevents razor-thin / screen-wide boxes', () {
    // Normal pothole
    const validPothole = Detection(100, 100, 250, 200, 0.85, 0); // w=150, h=100 (ar=1.5)
    expect(isGeometricallyValid(validPothole, 640, 480), isTrue);

    // Extreme razor-thin width artifact (e.g. w=620, h=10, ar=62)
    const razorThin = Detection(10, 100, 630, 110, 0.85, 0);
    expect(isGeometricallyValid(razorThin, 640, 480), isFalse);

    // Screen-covering hallucination
    const screenCovering = Detection(5, 5, 635, 475, 0.85, 0);
    expect(isGeometricallyValid(screenCovering, 640, 480), isFalse);
  });

  test('Minimum bounding-box size filter', () {
    const tinyBox = Detection(10, 10, 15, 18, 0.95, 0); // w=5, h=8, area=40
    const normalBox = Detection(50, 50, 150, 150, 0.85, 0); // w=100, h=100, area=10000

    expect(meetsMinSize(normalBox), isTrue);
    expect(meetsMinSize(tinyBox), isFalse);
  });

  test('Ground-plane physical size estimator converts pixels to centimetres', () {
    const estimator = GroundPlaneEstimator(
      cameraHeightCm: 15.0,
      pitchDeg: 25.0,
      fovHDeg: 66.0,
      fovVDeg: 50.0,
    );

    // Detection in lower half of image (near bottom where pothole is close to robot)
    const pothole = Detection(220, 340, 420, 440, 0.85, 0); // w=200px, h=100px, bottom at y=440 in 640x480
    final phys = estimator.estimate(pothole, 640, 480);

    expect(phys.isValid, isTrue);
    expect(phys.distanceCm, greaterThan(10.0));
    expect(phys.distanceCm, lessThan(100.0));
    expect(phys.widthCm, greaterThan(5.0));
    expect(phys.lengthCm, greaterThan(5.0));
    expect(phys.areaCm2, greaterThan(25.0));
  });

  test('Direction guidance: potholes on left suggest MOVE RIGHT or CONTINUE', () {
    const pLeft1 = Detection(30, 200, 120, 280, 0.85, 0);
    const pLeft2 = Detection(50, 350, 160, 420, 0.75, 0);

    final dir = analyseDirection([pLeft1, pLeft2], 640);
    expect(dir.leftCount, 2);
    expect(dir.centreCount, 0);
    expect(dir.rightCount, 0);
    expect(dir.recommendation, anyOf(Direction.right, Direction.centre));
  });

  test('Direction guidance: potholes spanning all regions trigger STOP', () {
    const pLeft = Detection(50, 200, 150, 300, 0.85, 0);
    const pCenter = Detection(270, 200, 370, 300, 0.85, 0);
    const pRight = Detection(500, 200, 600, 300, 0.85, 0);

    final dir = analyseDirection([pLeft, pCenter, pRight], 640);
    expect(dir.leftCount, 1);
    expect(dir.centreCount, 1);
    expect(dir.rightCount, 1);
    expect(dir.recommendation, Direction.stop);
  });

  test('Direction guidance: clear road returns CONTINUE', () {
    final dir = analyseDirection([], 640);
    expect(dir.leftCount, 0);
    expect(dir.centreCount, 0);
    expect(dir.rightCount, 0);
    expect(dir.recommendation, Direction.centre);
  });
}
