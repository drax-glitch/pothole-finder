import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'detection_config.dart';
import 'detector.dart';
import 'history_db.dart';
import 'mjpeg.dart';
import 'vision_math.dart';
import 'voice_service.dart';

final app = AppController();

/// Tracks ongoing pothole detections across frames with temporal stability
class _Track {
  int id;
  Detection box;
  DateTime firstSeen;
  DateTime lastSeen;
  int hitCount;
  bool isLogged;

  _Track({
    required this.id,
    required this.box,
    required this.firstSeen,
    required this.lastSeen,
    this.hitCount = 1,
    this.isLogged = false,
  });
}

// -----------------------------------------------------------------------------
// AppController
// -----------------------------------------------------------------------------

class AppController {
  final camera = CameraService();
  final detector = Detector();
  final db = HistoryDb();
  final voice = VoiceService();
  late SharedPreferences prefs;

  static const defaultCameraUrl = 'http://192.168.4.1:81/stream';
  String streamUrl = defaultCameraUrl;
  bool routerMode = false;
  double conf = kDefaultConf;
  bool vibrate = true;

  // Camera calibration settings for road-plane size measurement
  double cameraHeightCm = kDefaultCameraHeightCm;
  double cameraPitchDeg = kDefaultCameraPitchDeg;

  // Public notifiers observed by the UI
  final detecting = ValueNotifier<bool>(false);
  final result = ValueNotifier<DetectResult?>(null);
  final potholeCount = ValueNotifier<int>(0);
  final fps = ValueNotifier<double>(0);
  final inferMs = ValueNotifier<int>(0);
  final newHistory = ValueNotifier<int>(0);
  final historyVersion = ValueNotifier<int>(0);
  final lastError = ValueNotifier<String>('');

  // Internal
  bool _busy = false;
  DateTime _lastResult = DateTime.now();
  DateTime _lastDone = DateTime.now();
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSaveEvent = DateTime.fromMillisecondsSinceEpoch(0);

  int _nextTrackId = 1;
  final _tracks = <_Track>[];
  Timer? _clear;

  GroundPlaneEstimator get currentEstimator => GroundPlaneEstimator(
        cameraHeightCm: cameraHeightCm,
        pitchDeg: cameraPitchDeg,
      );

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    streamUrl = prefs.getString('url') ?? defaultCameraUrl;
    routerMode = prefs.getBool('router') ?? false;
    conf = prefs.getDouble('conf') ?? kDefaultConf;
    vibrate = prefs.getBool('vibrate') ?? true;
    voice.enabled = prefs.getBool('voice') ?? true;
    cameraHeightCm = prefs.getDouble('cam_h') ?? kDefaultCameraHeightCm;
    cameraPitchDeg = prefs.getDouble('cam_pitch') ?? kDefaultCameraPitchDeg;

    await detector.init();
    await voice.init();

    camera.latest.addListener(_onFrame);
    camera.start(streamUrl);

    // Clear stale result after 600 ms without new frames
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
    await prefs.setBool('voice', voice.enabled);
    await prefs.setDouble('cam_h', cameraHeightCm);
    await prefs.setDouble('cam_pitch', cameraPitchDeg);
  }

  void connect(String url) {
    streamUrl = url;
    saveSettings();
    camera.start(url);
  }

  void setDetecting(bool on) {
    if (on && !detector.ready) return;
    detecting.value = on;
    if (!on) {
      result.value = null;
      voice.stop();
    }
  }

  Future<void> _onFrame() async {
    if (!detecting.value || _busy || !detector.ready) return;

    // Frame throttle
    final now = DateTime.now();
    if (now.difference(_lastFrame).inMilliseconds < kFrameThrottleMs) return;
    _lastFrame = now;

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
    if (dt > 0) {
      fps.value = fps.value == 0 ? 1000 / dt : fps.value * 0.7 + (1000 / dt) * 0.3;
    }

    // Purge tracks that haven't been seen for 3.0 seconds
    _tracks.removeWhere((t) => now.difference(t.lastSeen) > const Duration(seconds: 3));

    // Match each detected box against active tracks using IoU & center distance
    for (final d in res.dets) {
      _Track? matched;
      for (final t in _tracks) {
        final overlap = iou(t.box, d);
        final distCenter = math.sqrt(math.pow(t.box.cx - d.cx, 2) + math.pow(t.box.cy - d.cy, 2));
        final maxDimension = math.max(d.w, d.h);

        // Good overlap or close center
        if (overlap > 0.25 || distCenter < maxDimension * 0.75) {
          matched = t;
          break;
        }
      }

      if (matched != null) {
        matched.box = d;
        matched.lastSeen = now;
        matched.hitCount++;

        // Only log once per track after confirmation (at least 2 consecutive detections)
        if (!matched.isLogged && matched.hitCount >= 2) {
          matched.isLogged = true;
          // Global save cooldown to prevent bursting database with identical frames
          if (now.difference(_lastSaveEvent).inMilliseconds >= 1200) {
            _lastSaveEvent = now;
            potholeCount.value++;
            if (vibrate) HapticFeedback.heavyImpact();
            _save(d, res, frame, matched.id);
          }
        }
      } else {
        // New track candidate
        _tracks.add(_Track(
          id: _nextTrackId++,
          box: d,
          firstSeen: now,
          lastSeen: now,
          hitCount: 1,
          isLogged: false,
        ));
      }
    }

    // Voice announcements
    if (res.dets.isNotEmpty) {
      final msg = voiceMessageFor(res.dets, res.direction);
      if (msg != null) voice.speak(msg);

      final dir = res.direction;
      if (dir.recommendation != Direction.centre) {
        voice.speak(dir.recommendation.voiceText);
      }
    }
  }

  Future<void> _save(Detection d, DetectResult res, Uint8List frame, int trackId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = p.join(dir.path, 'pothole_${trackId}_$ts.jpg');
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

  void dispose() {
    _clear?.cancel();
    camera.stop();
    voice.dispose();
  }
}
