import 'package:flutter/foundation.dart';
import 'detection_config.dart';
import 'vision_math.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VoiceService
//
// Wraps flutter_tts with:
//   • Enable / disable toggle (persisted by AppController).
//   • Per-message cooldown so the same alert is not repeated every frame.
//   • Global cooldown between any two announcements.
//
// flutter_tts is imported lazily so the build still works if the package is
// not yet added. Once you add flutter_tts to pubspec.yaml the real import
// below takes effect.
// ─────────────────────────────────────────────────────────────────────────────

// ignore: depend_on_referenced_packages
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  final FlutterTts _tts = FlutterTts();
  bool enabled = true;

  DateTime _lastSpoke  = DateTime.fromMillisecondsSinceEpoch(0);
  String   _lastText   = '';
  DateTime _lastTextTs = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> init() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      // Suppress unhandled-exception noise in debug builds.
      _tts.setErrorHandler((msg) => debugPrint('[TTS] error: $msg'));
    } catch (e) {
      debugPrint('[TTS] init error: $e');
    }
  }

  Future<void> speak(String text) async {
    if (!enabled) return;
    final now = DateTime.now();

    // Global cooldown: no announcement within kVoiceCooldownMs of the last.
    if (now.difference(_lastSpoke).inMilliseconds < kVoiceCooldownMs) return;

    // Per-message cooldown: same text within kVoiceRepeatMs is suppressed.
    if (text == _lastText &&
        now.difference(_lastTextTs).inMilliseconds < kVoiceRepeatMs) {
      return;
    }

    _lastSpoke  = now;
    _lastText   = text;
    _lastTextTs = now;

    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[TTS] speak error: $e');
    }
  }

  Future<void> stop() async {
    try { await _tts.stop(); } catch (_) {}
  }

  void dispose() { stop(); }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper: choose the appropriate voice alert for a detection result.
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the voice message to announce for [result], or null if silent.
String? voiceMessageFor(
  List<Detection> dets,
  DirectionResult dir,
) {
  if (dets.isEmpty) return null;

  // Count per-region.
  final l = dir.leftCount;
  final c = dir.centreCount;
  final r = dir.rightCount;

  // Multiple potholes across different regions.
  if (dets.length > 1) return 'Multiple potholes detected.';

  // Single pothole – location-specific.
  if (l > 0 && c == 0 && r == 0) return 'Pothole detected on the left.';
  if (r > 0 && c == 0 && l == 0) return 'Pothole detected on the right.';
  return 'Pothole detected ahead.';
}

