import 'package:flutter/material.dart';
import '../state.dart';
import '../theme.dart';
import 'photo_test.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Settings',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: C.yellow)),
          const SizedBox(height: 14),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Confidence threshold: ${(app.conf * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Slider(
                value: app.conf,
                min: 0.2,
                max: 0.9,
                divisions: 14,
                onChanged: (v) => setState(() => app.conf = v),
                onChangeEnd: (_) => app.saveSettings(),
              ),
              const Text(
                'Lower = finds more potholes but more false alarms. '
                'Raise it if shadows or manholes get boxes.',
                style: TextStyle(color: C.muted, fontSize: 13),
              ),
            ]),
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PhotoTestScreen())),
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
          Text('Model: ${app.detector.error ?? app.detector.info}',
              style: const TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 8),
          const Text(
            'Dataset credit: "pothole" Computer Vision Model by Yeeun Kim, Roboflow Universe, CC BY 4.0.',
            style: TextStyle(color: C.muted, fontSize: 12),
          ),
        ],
      );
}
