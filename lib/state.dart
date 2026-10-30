import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'detector.dart';
import 'history_db.dart';
import 'mjpeg.dart';
import 'vision_math.dart';

final app = AppController();

class _Track {
  Detection box;
  DateTime seen;
  _Track(this.box, this.seen);
}

/// Owns the camera, the detector, settings and the detection loop.
class AppController {
  final camera = CameraService();
  final detector = Detector();
  final db = HistoryDb();
  late SharedPreferences prefs;

  static const defaultCameraUrl = 'http://192.168.4.1:81/stream';
  String streamUrl = defaultCameraUrl;
  bool routerMode = false;
  double conf = 0.5;
  bool vibrate = true;

  final detecting = ValueNotifier<bool>(false);
  final result = ValueNotifier<DetectResult?>(null);
  final potholeCount = ValueNotifier<int>(0);
  final fps = ValueNotifier<double>(0);
  final inferMs = ValueNotifier<int>(0);
  final newHistory = ValueNotifier<int>(0);
  final historyVersion = ValueNotifier<int>(0);
  final lastError = ValueNotifier<String>('');

  bool _busy = false;
  DateTime _lastResult = DateTime.now();
  DateTime _lastDone = DateTime.now();
  final _tracks = <_Track>[];
  Timer? _clear;

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    streamUrl = prefs.getString('url') ?? defaultCameraUrl;
    routerMode = prefs.getBool('router') ?? false;
    conf = prefs.getDouble('conf') ?? 0.5;
    vibrate = prefs.getBool('vibrate') ?? true;
    await detector.init();
    camera.latest.addListener(_onFrame);
    camera.start(streamUrl);
    _clear = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (result.value != null &&
          DateTime.now().difference(_lastResult) > const Duration(milliseconds: 600)) {
        result.value = null;
      }
    });
  }

  Future<void> saveSettings() async {
    await prefs.setString('url', streamUrl);
    await prefs.setBool('router', routerMode);
    await prefs.setDouble('conf', conf);
    await prefs.setBool('vibrate', vibrate);
  }

  void connect(String url) {
    streamUrl = url;
    saveSettings();
    camera.start(url);
  }

  void setDetecting(bool on) {
    if (on && !detector.ready) return;
    detecting.value = on;
    if (!on) result.value = null;
  }

  Future<void> _onFrame() async {
    if (!detecting.value || _busy || !detector.ready) return;
    final frame = camera.latest.value;
    if (frame == null) return;
    _busy = true;
    try {
      final res = await detector.detect(frame, conf);
      if (detecting.value) _handle(res, frame);
      lastError.value = '';
    } catch (e) {
      lastError.value = '$e';
    } finally {
      _busy = false;
    }
  }

  void _handle(DetectResult res, Uint8List frame) {
    final now = DateTime.now();
    result.value = res.dets.isEmpty ? null : res;
    _lastResult = now;
    inferMs.value = res.inferMs;
    final dt = now.difference(_lastDone).inMilliseconds;
    _lastDone = now;
    if (dt > 0) fps.value = fps.value == 0 ? 1000 / dt : fps.value * 0.7 + (1000 / dt) * 0.3;

    _tracks.removeWhere((t) => now.difference(t.seen) > const Duration(seconds: 2));
    for (final d in res.dets) {
      _Track? match;
      for (final t in _tracks) {
        final near = (t.box.cx - d.cx).abs() < d.w && (t.box.cy - d.cy).abs() < d.h;
        if (iou(t.box, d) > 0.1 || near) {
          match = t;
          break;
        }
      }
      if (match != null) {
        match.box = d;
        match.seen = now;
      } else {
        _tracks.add(_Track(d, now));
        potholeCount.value++;
        if (vibrate) HapticFeedback.heavyImpact();
        _save(d, res, frame);
      }
    }
  }

  Future<void> _save(Detection d, DetectResult res, Uint8List frame) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = p.join(dir.path, 'pothole_$ts.jpg');
      await File(path).writeAsBytes(frame);
      final sev = rateSeverity(d, res.frameW, res.frameH);
      await db.insert({
        'ts': ts,
        'conf': d.conf,
        'l': d.l,
        't': d.t,
        'r': d.r,
        'b': d.b,
        'fw': res.frameW,
        'fh': res.frameH,
        'severity': sev.label,
        'score': sev.score,
        'image': path,
      });
      newHistory.value++;
      historyVersion.value++;
    } catch (e) {
      lastError.value = 'Could not save to history: $e';
    }
  }

  void resetCount() {
    potholeCount.value = 0;
    _tracks.clear();
  }
}
