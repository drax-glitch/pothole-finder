import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:potfinder/mjpeg.dart';
import 'package:potfinder/vision_math.dart';

void main() {
  test('MJPEG splitter finds frames across chunks', () {
    final f1 = [0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9];
    final f2 = [0xFF, 0xD8, 9, 8, 0xFF, 0xD9];
    final stream = [0, 0, ...f1, 5, 5, 5, ...f2];
    final got = <Uint8List>[];
    final sp = MjpegSplitter();
    for (var i = 0; i < stream.length; i += 3) {
      sp.add(stream.sublist(i, (i + 3).clamp(0, stream.length)), got.add);
    }
    expect(got.length, 2);
    expect(got[0], f1);
    expect(got[1], f2);
  });

  test('letterbox 640x480 into 640x640', () {
    final lb = Letterbox.of(640, 480, 640, 640);
    expect(lb.scale, 1.0);
    expect(lb.padY, 80);
    expect(lb.origY(80), 0);
    expect(lb.origY(560), 480);
  });

  test('NMS removes duplicates', () {
    final a = const Detection(0, 0, 100, 100, 0.9, 0);
    final b = const Detection(5, 5, 105, 105, 0.8, 0);
    final c = const Detection(300, 300, 400, 400, 0.7, 0);
    expect(nms([a, b, c]).length, 2);
  });

  test('url normalisation', () {
    expect(normalizeStreamUrl('192.168.1.45'), 'http://192.168.1.45:81/stream');
    expect(normalizeStreamUrl('http://192.168.4.1:81/stream'), 'http://192.168.4.1:81/stream');
  });
}
