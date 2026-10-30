import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Cuts an MJPEG byte stream into complete JPEG frames (FFD8 ... FFD9).
class MjpegSplitter {
  Uint8List _b = Uint8List(1 << 18);
  int _len = 0, _scan = 0, _start = -1;
  static const _maxFrame = 3 * 1024 * 1024;

  void add(List<int> chunk, void Function(Uint8List frame) onFrame) {
    if (_len + chunk.length > _b.length) {
      var n = _b.length;
      while (n < _len + chunk.length) {
        n *= 2;
      }
      final nb = Uint8List(n)..setRange(0, _len, _b);
      _b = nb;
    }
    _b.setRange(_len, _len + chunk.length, chunk);
    _len += chunk.length;

    while (true) {
      if (_start < 0) {
        var found = -1;
        for (var i = _scan; i < _len - 1; i++) {
          if (_b[i] == 0xFF && _b[i + 1] == 0xD8) {
            found = i;
            break;
          }
        }
        if (found < 0) {
          if (_len > 0) {
            _b[0] = _b[_len - 1];
            _len = 1;
          }
          _scan = 0;
          return;
        }
        _start = found;
        _scan = found + 2;
      }
      var end = -1;
      for (var i = _scan; i < _len - 1; i++) {
        if (_b[i] == 0xFF && _b[i + 1] == 0xD9) {
          end = i;
          break;
        }
      }
      if (end < 0) {
        _scan = math.max(_start + 2, _len - 1);
        if (_len - _start > _maxFrame) {
          _len = 0;
          _scan = 0;
          _start = -1;
        }
        return;
      }
      onFrame(Uint8List.fromList(_b.sublist(_start, end + 2)));
      final rest = _len - (end + 2);
      _b.setRange(0, rest, _b, end + 2);
      _len = rest;
      _scan = 0;
      _start = -1;
    }
  }
}

enum CamState { idle, connecting, streaming, reconnecting, offline }

String normalizeStreamUrl(String input) {
  var s = input.trim();
  if (!s.startsWith('http')) s = 'http://$s';
  final u = Uri.parse(s);
  final port = u.hasPort ? u.port : 81;
  final path = (u.path.isEmpty || u.path == '/') ? '/stream' : u.path;
  return 'http://${u.host}:$port$path';
}

/// Keeps one connection to the ESP32-CAM stream; only the newest frame is kept.
class CameraService {
  final latest = ValueNotifier<Uint8List?>(null);
  final state = ValueNotifier<CamState>(CamState.idle);
  final message = ValueNotifier<String>('');

  int _gen = 0;
  HttpClient? _client;
  DateTime _lastFrame = DateTime.now();
  Timer? _watch;

  void start(String url) {
    stop();
    final g = ++_gen;
    state.value = CamState.connecting;
    message.value = '';
    _lastFrame = DateTime.now();
    _watch = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.value == CamState.streaming &&
          DateTime.now().difference(_lastFrame) > const Duration(seconds: 3)) {
        state.value = CamState.offline;
        message.value = 'No frames for 3 seconds';
      }
    });
    _loop(url, g);
  }

  void stop() {
    _gen++;
    _watch?.cancel();
    _client?.close(force: true);
    _client = null;
    state.value = CamState.idle;
    latest.value = null;
  }

  Future<void> _loop(String url, int g) async {
    var backoff = 1;
    while (g == _gen) {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      _client = client;
      try {
        final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 5));
        final resp = await req.close().timeout(const Duration(seconds: 5));
        if (resp.statusCode != 200) throw HttpException('HTTP ${resp.statusCode}');
        final splitter = MjpegSplitter();
        await for (final chunk in resp.timeout(const Duration(seconds: 5))) {
          if (g != _gen) break;
          splitter.add(chunk, (frame) {
            latest.value = frame;
            _lastFrame = DateTime.now();
            backoff = 1;
            if (state.value != CamState.streaming) state.value = CamState.streaming;
          });
        }
        if (g == _gen) throw const SocketException('Stream ended');
      } catch (e) {
        if (g != _gen) return;
        message.value = e is TimeoutException ? 'Camera not responding' : '$e';
        state.value = backoff >= 8 ? CamState.offline : CamState.reconnecting;
        await Future<void>.delayed(Duration(seconds: backoff));
        backoff = math.min(8, backoff * 2);
      } finally {
        client.close(force: true);
      }
    }
  }
}
