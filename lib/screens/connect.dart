import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../mjpeg.dart';
import '../state.dart';
import '../theme.dart';

enum _S { idle, run, ok, fail }

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late bool _router = app.routerMode;
  late final _ctl = TextEditingController(text: app.streamUrl);
  final _st = [_S.idle, _S.idle, _S.idle];
  final _msg = ['', '', ''];
  bool _testing = false;

  static const _names = ['Network reachable', 'Camera responds', 'Frames flowing'];

  void _set(int i, _S s, [String m = '']) {
    if (!mounted) return;
    setState(() {
      _st[i] = s;
      _msg[i] = m;
    });
  }

  Future<void> _test() async {
    FocusScope.of(context).unfocus();
    late final String url;
    try {
      url = normalizeStreamUrl(_ctl.text);
    } catch (_) {
      _set(0, _S.fail, 'That address is not valid. Example: http://192.168.4.1:81/stream');
      return;
    }
    final uri = Uri.parse(url);
    setState(() {
      _testing = true;
      for (var i = 0; i < 3; i++) {
        _st[i] = _S.idle;
        _msg[i] = '';
      }
    });
    app.camera.stop(); // the camera serves only one viewer at a time
    await Future<void>.delayed(const Duration(milliseconds: 400));
    var ok = false;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      _set(0, _S.run);
      try {
        final s = await Socket.connect(uri.host, uri.port, timeout: const Duration(seconds: 4));
        s.destroy();
        _set(0, _S.ok);
      } catch (_) {
        _set(0, _S.fail, 'Cannot reach ${uri.host}. Join the camera Wi-Fi (or same network) and check the IP.');
        return;
      }
      _set(1, _S.run);
      HttpClientResponse resp;
      try {
        final req = await client.getUrl(uri).timeout(const Duration(seconds: 5));
        resp = await req.close().timeout(const Duration(seconds: 5));
        if (resp.statusCode != 200) throw HttpException('HTTP ${resp.statusCode}');
        _set(1, _S.ok);
      } catch (e) {
        _set(1, _S.fail, 'No answer from the camera ($e). Close any browser tab showing the stream, check power.');
        return;
      }
      _set(2, _S.run);
      try {
        final sp = MjpegSplitter();
        var got = false;
        await for (final ch in resp.timeout(const Duration(seconds: 5))) {
          sp.add(ch, (_) => got = true);
          if (got) break;
        }
        if (!got) throw Exception('stream ended');
        _set(2, _S.ok);
        ok = true;
      } catch (_) {
        _set(2, _S.fail, 'No video frame received. The address must end with :81/stream.');
      }
    } finally {
      client.close(force: true);
      if (mounted) setState(() => _testing = false);
      app.routerMode = _router;
      app.connect(url);
      if (ok) _ctl.text = url;
    }
  }

  void _connect() {
    FocusScope.of(context).unfocus();
    final url = normalizeStreamUrl(_ctl.text);
    _ctl.text = url;
    app.routerMode = _router;
    app.connect(url);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Connecting... open the Live tab')));
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Connect camera',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: C.yellow)),
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Camera Wi-Fi'), icon: Icon(Icons.router)),
              ButtonSegment(value: true, label: Text('Home router'), icon: Icon(Icons.home)),
            ],
            selected: {_router},
            onSelectionChanged: (s) => setState(() {
              _router = s.first;
              _ctl.text = _router ? 'http://192.168.1.' : AppController.defaultCameraUrl;
            }),
          ),
          const SizedBox(height: 8),
          Text(
            _router
                ? 'Camera joined your router/hotspot. Type its IP (see Serial Monitor), e.g. 192.168.1.45'
                : 'Join the Wi-Fi named PotFinder-CAM (password 12345678) first.',
            style: const TextStyle(color: C.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Stream address'),
          ),
          const SizedBox(height: 14),
          FilledButton(onPressed: _testing ? null : _connect, child: const Text('Connect')),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _testing ? null : _test,
            child: Text(_testing ? 'Testing...' : 'Test connection'),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < 3; i++) _row(i),
          const SizedBox(height: 10),
          const Panel(
            child: Text(
              'Tip: turn off "Switch to mobile data automatically" in your phone Wi-Fi '
              'settings, and answer Yes if Android asks to stay connected to a network with no internet.',
              style: TextStyle(color: C.muted, fontSize: 13),
            ),
          ),
        ],
      );

  Widget _row(int i) {
    final (icon, color) = switch (_st[i]) {
      _S.idle => (Icons.radio_button_unchecked, C.muted),
      _S.run => (Icons.hourglass_top, C.yellow),
      _S.ok => (Icons.check_circle, C.mint),
      _S.fail => (Icons.cancel, C.warn),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_names[i], style: const TextStyle(fontWeight: FontWeight.w700)),
            if (_msg[i].isNotEmpty) Text(_msg[i], style: const TextStyle(color: C.warn, fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}
