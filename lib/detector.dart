import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'vision_math.dart';

const kModelAsset = 'assets/models/pothole_model.tflite';

class DetectResult {
  final List<Detection> dets;
  final int frameW, frameH, preMs, inferMs;
  final List<double> topScores;
  const DetectResult(this.dets, this.frameW, this.frameH, this.preMs, this.inferMs, this.topScores);
}

/// Loads the model in a background isolate so the video never stutters.
class Detector {
  SendPort? _port;
  String? error;
  String info = '';
  final status = ValueNotifier<String>('Loading model...');
  bool get ready => _port != null;

  Future<void> init() async {
    ByteData data;
    try {
      data = await rootBundle.load(kModelAsset);
    } catch (_) {
      error = 'Model not found. Put pothole_model.tflite in assets/models/ and do a full rebuild.';
      status.value = error!;
      return;
    }
    try {
      final rp = ReceivePort();
      await Isolate.spawn(_worker, [rp.sendPort, data.buffer.asUint8List()]);
      final m = await rp.first as Map;
      if (m['error'] != null) {
        error = m['error'] as String;
        status.value = error!;
        return;
      }
      _port = m['port'] as SendPort;
      info = 'input ${m['in']}  output ${m['out']}';
      status.value = 'Model ready';
    } catch (e) {
      error = 'Model failed to start: $e';
      status.value = error!;
    }
  }

  Future<DetectResult> detect(Uint8List imageBytes, double threshold) async {
    final rp = ReceivePort();
    _port!.send([rp.sendPort, imageBytes, threshold]);
    final m = await rp.first as Map;
    if (m['error'] != null) throw Exception(m['error']);
    final dets = <Detection>[];
    for (final e in (m['dets'] as List)) {
      final v = (e as List).map((x) => (x as num).toDouble()).toList();
      dets.add(Detection(v[0], v[1], v[2], v[3], v[4], v[5].toInt()));
    }
    return DetectResult(
      dets,
      m['w'] as int,
      m['h'] as int,
      m['pre'] as int,
      m['inf'] as int,
      (m['top'] as List).map((x) => (x as num).toDouble()).toList(),
    );
  }
}

// ---------------- background isolate ----------------

void _worker(List<dynamic> init) {
  final main = init[0] as SendPort;
  final bytes = init[1] as Uint8List;
  Interpreter interp;
  try {
    interp = Interpreter.fromBuffer(bytes, options: InterpreterOptions()..threads = 4);
  } catch (e) {
    main.send({'error': 'Could not load model: $e'});
    return;
  }
  final inShape = interp.getInputTensor(0).shape;
  final outShape = interp.getOutputTensor(0).shape;
  final rp = ReceivePort();
  main.send({'port': rp.sendPort, 'in': inShape, 'out': outShape});
  rp.listen((dynamic m) {
    final msg = m as List;
    final reply = msg[0] as SendPort;
    try {
      reply.send(_process(interp, inShape, outShape, msg[1] as Uint8List, msg[2] as double));
    } catch (e) {
      reply.send({'error': '$e'});
    }
  });
}

Map<String, dynamic> _process(
    Interpreter interp, List<int> inS, List<int> outS, Uint8List bytes, double thr) {
  final sw = Stopwatch()..start();

  // Input layout is read from the model: [1,3,H,W] (channels first) or [1,H,W,3].
  final chw = inS.length == 4 && inS[1] == 3;
  final inH = chw ? inS[2] : inS[1];
  final inW = chw ? inS[3] : inS[2];

  var im = img.decodeImage(bytes);
  if (im == null) throw Exception('Could not decode image');
  im = img.bakeOrientation(im);
  final W = im.width, H = im.height;

  // Letterbox (gray 114 padding), RGB, 0-1 float.
  final lb = Letterbox.of(W, H, inW, inH);
  final rs = (lb.newW == W && lb.newH == H)
      ? im
      : img.copyResize(im, width: lb.newW, height: lb.newH, interpolation: img.Interpolation.linear);
  final plane = inW * inH;
  final input = Float32List(plane * 3)..fillRange(0, plane * 3, 114 / 255);
  for (var y = 0; y < lb.newH; y++) {
    for (var x = 0; x < lb.newW; x++) {
      final p = rs.getPixel(x, y);
      final idx = (y + lb.padY) * inW + (x + lb.padX);
      final r = p.r / 255.0, g = p.g / 255.0, b = p.b / 255.0;
      if (chw) {
        input[idx] = r;
        input[plane + idx] = g;
        input[2 * plane + idx] = b;
      } else {
        input[idx * 3] = r;
        input[idx * 3 + 1] = g;
        input[idx * 3 + 2] = b;
      }
    }
  }
  final pre = sw.elapsedMilliseconds;
  sw.reset();

  final A = outS[1], B = outS[2];
  final output = List.generate(1, (_) => List.generate(A, (_) => List<double>.filled(B, 0.0)));
  interp.run(input.buffer, output);
  final inf = sw.elapsedMilliseconds;

  // Output is [1, 4+C, N] (usual) or [1, N, 4+C].
  final transposed = A < B;
  final n = transposed ? B : A;
  final nf = transposed ? A : B;
  double g(int i, int k) => transposed ? output[0][k][i] : output[0][i][k];
  final nCls = nf - 4;

  // Boxes are normalised 0-1 (typical TFLite export) or in input pixels.
  var maxCoord = 0.0;
  for (var i = 0; i < n; i++) {
    for (var k = 0; k < 4; k++) {
      maxCoord = math.max(maxCoord, g(i, k));
    }
  }
  final norm = maxCoord <= 1.5;
  final sx = norm ? inW.toDouble() : 1.0, sy = norm ? inH.toDouble() : 1.0;

  final top = <double>[0, 0, 0];
  final cands = <Detection>[];
  for (var i = 0; i < n; i++) {
    var best = 0.0;
    var bc = 0;
    for (var c = 0; c < nCls; c++) {
      final s = g(i, 4 + c);
      if (s > best) {
        best = s;
        bc = c;
      }
    }
    if (best > top[2]) {
      top[2] = best;
      top.sort((a, b) => b.compareTo(a));
    }
    if (best < thr) continue;
    final cx = g(i, 0) * sx, cy = g(i, 1) * sy, w = g(i, 2) * sx, h = g(i, 3) * sy;
    final l = lb.origX(cx - w / 2).clamp(0.0, W.toDouble());
    final t = lb.origY(cy - h / 2).clamp(0.0, H.toDouble());
    final r = lb.origX(cx + w / 2).clamp(0.0, W.toDouble());
    final b = lb.origY(cy + h / 2).clamp(0.0, H.toDouble());
    if (r - l < 2 || b - t < 2) continue;
    cands.add(Detection(l, t, r, b, best, bc));
  }
  cands.sort((a, b) => b.conf.compareTo(a.conf));
  final kept = nms(cands.take(300).toList());

  return {
    'dets': kept.map((d) => [d.l, d.t, d.r, d.b, d.conf, d.cls.toDouble()]).toList(),
    'w': W,
    'h': H,
    'pre': pre,
    'inf': inf,
    'top': top,
  };
}
