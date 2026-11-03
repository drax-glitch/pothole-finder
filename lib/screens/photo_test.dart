import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../detector.dart';
import '../overlay.dart';
import '../state.dart';
import '../theme.dart';
import '../vision_math.dart';

/// Runs a gallery photo through the EXACT same pipeline as live frames,
/// with full pixel and physical metric size breakdown.
class PhotoTestScreen extends StatefulWidget {
  const PhotoTestScreen({super.key});
  @override
  State<PhotoTestScreen> createState() => _PhotoTestScreenState();
}

class _PhotoTestScreenState extends State<PhotoTestScreen> {
  Uint8List? _bytes;
  DetectResult? _res;
  double _used = 0.30;
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
      appBar: AppBar(
        title: const Text('Test model on a photo'),
        backgroundColor: C.asphalt,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.photo_library),
            label: Text(_busy ? 'Analyzing image...' : 'Pick photo from gallery'),
          ),
          const SizedBox(height: 14),
          if (_bytes != null && r != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: r.frameW / r.frameH,
                child: Stack(fit: StackFit.expand, children: [
                  Image.memory(_bytes!, fit: BoxFit.contain),
                  CustomPaint(
                    painter: DetBoxPainter(
                      r.dets,
                      r.frameW,
                      r.frameH,
                      estimator: r.estimator,
                      showPhysicalUnits: true,
                    ),
                  ),
                ]),
              ),
            ),
          if (_err.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_err, style: const TextStyle(color: C.warn)),
            ),
          if (r != null) ...[
            const SizedBox(height: 12),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(
                      r.dets.isEmpty
                          ? 'No pothole found above ${(_used * 100).round()}% conf'
                          : '${r.dets.length} Pothole${r.dets.length == 1 ? '' : 's'} Detected',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const Spacer(),
                    Text(
                      '${r.frameW}×${r.frameH} px',
                      style: const TextStyle(color: C.muted, fontSize: 12),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  if (r.dets.isEmpty)
                    const Text(
                      'Try lowering the confidence threshold or selecting an image with clearer road lighting.',
                      style: TextStyle(color: C.muted, fontSize: 13),
                    )
                  else
                    for (var i = 0; i < r.dets.length; i++) ...[
                      _DetailedMeasurementCard(index: i + 1, d: r.dets[i], result: r),
                      if (i < r.dets.length - 1) const SizedBox(height: 8),
                    ],
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 6),
                  Text(
                    'Preprocess: ${r.preMs} ms   |   Inference: ${r.inferMs} ms',
                    style: const TextStyle(color: C.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Top 3 proposals: ${r.topScores.map((s) => '${(s * 100).toStringAsFixed(1)}%').join(', ')}',
                    style: const TextStyle(color: C.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pipeline: ${r.candidateCount} cands -> ${r.afterNmsCount} post-NMS -> ${r.afterSizeCount} final',
                    style: const TextStyle(color: C.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (r.dets.isEmpty && _used > 0.20) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _busy ? null : () => _run(0.20),
                child: const Text('Retry at 20% threshold'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DetailedMeasurementCard extends StatelessWidget {
  final int index;
  final Detection d;
  final DetectResult result;

  const _DetailedMeasurementCard({
    required this.index,
    required this.d,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final sev = rateSeverity(d, result.frameW, result.frameH);
    final sevCol = severityColor(sev.label);
    final phys = result.physicalSizeOf(d);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: C.asphalt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: C.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: sevCol.withAlpha(40),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: sevCol),
              ),
              child: Text(
                'Pothole #$index',
                style: TextStyle(color: sevCol, fontWeight: FontWeight.w900, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(d.conf * 100).toStringAsFixed(1)}% Confidence',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const Spacer(),
            Text(
              sev.label,
              style: TextStyle(color: sevCol, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ]),
          const SizedBox(height: 8),
          // Pixel size metrics
          Row(children: [
            Expanded(
              child: _MetricBadge(
                label: 'Width (px)',
                value: '${d.w.round()} px',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _MetricBadge(
                label: 'Height (px)',
                value: '${d.h.round()} px',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _MetricBadge(
                label: 'Area (px²)',
                value: '${d.area.round()} px²',
              ),
            ),
          ]),
          const SizedBox(height: 6),
          // Estimated physical ground size metrics
          if (phys.isValid)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: C.panel,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: C.line.withAlpha(100)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.straighten, size: 16, color: C.mint),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Ground estimate: ~${phys.widthCm.toStringAsFixed(1)} cm (W) × '
                      '${phys.lengthCm.toStringAsFixed(1)} cm (L)  |  '
                      'Footprint: ~${phys.areaCm2.toStringAsFixed(0)} cm²  |  '
                      'Dist: ~${phys.distanceCm.toStringAsFixed(0)} cm',
                      style: const TextStyle(color: C.mint, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  final String label;
  final String value;
  const _MetricBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: C.panel,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(children: [
          Text(label, style: const TextStyle(color: C.muted, fontSize: 10)),
          Text(value, style: const TextStyle(color: C.text, fontWeight: FontWeight.w800, fontSize: 11)),
        ]),
      );
}
