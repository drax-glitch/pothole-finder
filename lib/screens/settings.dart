import 'package:flutter/material.dart';
import '../detection_config.dart';
import '../state.dart';
import '../theme.dart';
import 'photo_test.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _hCtl =
      TextEditingController(text: app.cameraHeightCm.toStringAsFixed(1));
  late final TextEditingController _pitchCtl =
      TextEditingController(text: app.cameraPitchDeg.toStringAsFixed(1));

  @override
  void dispose() {
    _hCtl.dispose();
    _pitchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Settings',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: C.yellow)),
          const SizedBox(height: 14),

          // Confidence threshold
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Confidence threshold: ${(app.conf * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Slider(
                value: app.conf,
                min: 0.15,
                max: 0.90,
                divisions: 15,
                label: '${(app.conf * 100).round()}%',
                onChanged: (v) => setState(() => app.conf = v),
                onChangeEnd: (_) => app.saveSettings(),
              ),
              const Text(
                'Lower threshold -> more detections but more false positives.',
                style: TextStyle(color: C.muted, fontSize: 12),
              ),
              Text(
                'Default (detection_config.dart): ${(kDefaultConf * 100).round()}%',
                style: const TextStyle(color: C.muted, fontSize: 12),
              ),
            ]),
          ),
          const SizedBox(height: 10),

          // Ground Plane & Physical Measurement Calibration
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.architecture, size: 18, color: C.mint),
                SizedBox(width: 8),
                Text('Road-Plane Size Calibration',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ]),
              const SizedBox(height: 8),
              const Text(
                'Calibrates physical cm calculation from camera mounting geometry.',
                style: TextStyle(color: C.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _hCtl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Cam Height (cm)',
                      isDense: true,
                    ),
                    onChanged: (v) {
                      final n = double.tryParse(v);
                      if (n != null && n > 0) {
                        app.cameraHeightCm = n;
                        app.saveSettings();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _pitchCtl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Tilt Pitch (deg)',
                      isDense: true,
                    ),
                    onChanged: (v) {
                      final n = double.tryParse(v);
                      if (n != null && n >= 0 && n <= 85) {
                        app.cameraPitchDeg = n;
                        app.saveSettings();
                      }
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              const Text(
                'Note: Pixel dimensions can only be projected to physical centimetres when camera height and tilt are known.',
                style: TextStyle(color: C.muted, fontSize: 11),
              ),
            ]),
          ),
          const SizedBox(height: 10),

          // Minimum size & outlier filter parameters
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Bounding Box Size Filtering',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              _kv('Min Width', '${kMinBoxWidth.round()} px'),
              _kv('Min Height', '${kMinBoxHeight.round()} px'),
              _kv('Min Area', '${kMinBoxArea.round()} px²'),
              _kv('IoU Threshold', '$kNmsIouThreshold'),
              _kv('Max Proposals', '$kMaxCandidates'),
              _kv('Throttle Rate', '$kFrameThrottleMs ms'),
              const SizedBox(height: 6),
              const Text(
                'Filters out single-pixel spikes and prevents duplicate boxes.',
                style: TextStyle(color: C.muted, fontSize: 11),
              ),
            ]),
          ),
          const SizedBox(height: 10),

          // Vibrate
          Panel(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vibrate on new pothole'),
              value: app.vibrate,
              onChanged: (v) {
                setState(() => app.vibrate = v);
                app.saveSettings();
              },
            ),
          ),
          const SizedBox(height: 10),

          // Voice alerts
          Panel(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Voice alerts'),
              subtitle: const Text(
                'Announces pothole detections and direction suggestions.',
                style: TextStyle(color: C.muted, fontSize: 12),
              ),
              value: app.voice.enabled,
              onChanged: (v) {
                setState(() => app.voice.enabled = v);
                app.saveSettings();
              },
            ),
          ),
          const SizedBox(height: 14),

          // Actions
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const PhotoTestScreen())),
            icon: const Icon(Icons.image_search),
            label: const Text('Test model on a photo'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Clear history?'),
                  content: const Text('All saved potholes and images will be deleted.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear')),
                  ],
                ),
              );
              if (ok == true) {
                await app.db.clear();
                app.historyVersion.value++;
              }
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Clear history'),
          ),
          const SizedBox(height: 18),

          Text(
            'Model: ${app.detector.error ?? app.detector.info}',
            style: const TextStyle(color: C.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          const Text(
            'Dataset credit: "pothole" Computer Vision Model by Yeeun Kim, Roboflow Universe, CC BY 4.0.',
            style: TextStyle(color: C.muted, fontSize: 12),
          ),
        ],
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(color: C.muted, fontSize: 12))),
          Text(v, style: const TextStyle(color: C.text, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}
