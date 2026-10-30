import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../detector.dart';
import '../overlay.dart';
import '../state.dart';
import '../theme.dart';

/// Runs a gallery photo through the SAME pipeline as live frames.
class PhotoTestScreen extends StatefulWidget {
  const PhotoTestScreen({super.key});
  @override
  State<PhotoTestScreen> createState() => _PhotoTestScreenState();
}

class _PhotoTestScreenState extends State<PhotoTestScreen> {
  Uint8List? _bytes;
  DetectResult? _res;
  double _used = 0.5;
  String _err = '';
  bool _busy = false;

  Future<void> _pick() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f == null) return;
    _bytes = await f.readAsBytes();
    await _run(app.conf);
  }

  Future<void> _run(double thr) async {
    if (_bytes == null) return;
    if (!app.detector.ready) {
      setState(() => _err = app.detector.error ?? 'Model not ready');
      return;
    }
    setState(() {
      _busy = true;
      _err = '';
      _used = thr;
    });
    try {
      final r = await app.detector.detect(_bytes!, thr);
      if (mounted) setState(() => _res = r);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _res;
    return Scaffold(
      appBar: AppBar(title: const Text('Test model on a photo'), backgroundColor: C.asphalt),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        FilledButton.icon(
          onPressed: _busy ? null : _pick,
          icon: const Icon(Icons.photo_library),
          label: Text(_busy ? 'Detecting...' : 'Pick photo from gallery'),
        ),
        const SizedBox(height: 14),
        if (_bytes != null && r != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: r.frameW / r.frameH,
              child: Stack(fit: StackFit.expand, children: [
                Image.memory(_bytes!, fit: BoxFit.contain),
                CustomPaint(painter: DetBoxPainter(r.dets, r.frameW, r.frameH)),
              ]),
            ),
          ),
        if (_err.isNotEmpty) Text(_err, style: const TextStyle(color: C.warn)),
        if (r != null) ...[
          const SizedBox(height: 12),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                r.dets.isEmpty
                    ? 'No pothole found above ${(_used * 100).round()}% confidence'
                    : 'Potholes found: ${r.dets.length}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              for (final d in r.dets) Text('  Pothole ${(d.conf * 100).round()}%  (${d.w.round()} x ${d.h.round()} px)'),
              const SizedBox(height: 6),
              Text('Preprocess ${r.preMs} ms   Inference ${r.inferMs} ms',
                  style: const TextStyle(color: C.muted, fontSize: 13)),
              Text('Top raw scores: ${r.topScores.map((s) => '${(s * 100).toStringAsFixed(1)}%').join(', ')}',
                  style: const TextStyle(color: C.muted, fontSize: 13)),
            ]),
          ),
          if (r.dets.isEmpty && _used > 0.3) ...[
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _busy ? null : () => _run(0.3), child: const Text('Retry at 30%')),
          ],
        ],
      ]),
    );
  }
}
