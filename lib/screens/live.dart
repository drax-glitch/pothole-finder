import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../mjpeg.dart';
import '../overlay.dart';
import '../detector.dart';
import '../state.dart';
import '../theme.dart';

class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            const Expanded(
              child: Text('PotFinder',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: C.yellow)),
            ),
            const _StatusPill(),
          ]),
          const SizedBox(height: 14),
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: Colors.black,
                child: ValueListenableBuilder<Uint8List?>(
                  valueListenable: app.camera.latest,
                  builder: (_, frame, __) => frame == null
                      ? const _Placeholder()
                      : Stack(fit: StackFit.expand, children: [
                          Image.memory(frame, gaplessPlayback: true, fit: BoxFit.contain),
                          ValueListenableBuilder<DetectResult?>(
                            valueListenable: app.result,
                            builder: (_, r, __) => r == null
                                ? const SizedBox.shrink()
                                : CustomPaint(painter: DetBoxPainter(r.dets, r.frameW, r.frameH)),
                          ),
                          Positioned(
                            top: 8,
                            left: 8,
                            child: ValueListenableBuilder<bool>(
                              valueListenable: app.detecting,
                              builder: (_, on, __) => on
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                          color: C.mint, borderRadius: BorderRadius.circular(6)),
                                      child: const Text('DETECTING',
                                          style: TextStyle(
                                              color: C.asphalt, fontWeight: FontWeight.w800, fontSize: 11)),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<String>(
            valueListenable: app.detector.status,
            builder: (_, s, __) => app.detector.error == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Panel(
                      color: const Color(0x33FF6A4D),
                      child: Text(s, style: const TextStyle(color: C.warn)),
                    ),
                  ),
          ),
          Row(children: [
            Expanded(child: _Tile('Potholes', app.potholeCount, (v) => '$v')),
            const SizedBox(width: 10),
            Expanded(child: _Tile('FPS', app.fps, (v) => v.toStringAsFixed(1))),
            const SizedBox(width: 10),
            Expanded(child: _Tile('ms / frame', app.inferMs, (v) => '$v')),
          ]),
          const SizedBox(height: 14),
          ValueListenableBuilder<bool>(
            valueListenable: app.detecting,
            builder: (_, on, __) => FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: on ? C.warn : C.yellow,
                foregroundColor: on ? Colors.white : C.asphalt,
              ),
              onPressed: app.detector.ready ? () => app.setDetecting(!on) : null,
              icon: Icon(on ? Icons.stop : Icons.play_arrow),
              label: Text(on ? 'Stop detecting' : 'Start detecting'),
            ),
          ),
          TextButton(onPressed: app.resetCount, child: const Text('Reset count')),
          ValueListenableBuilder<String>(
            valueListenable: app.lastError,
            builder: (_, e, __) => e.isEmpty
                ? const SizedBox.shrink()
                : Text(e, style: const TextStyle(color: C.warn, fontSize: 12)),
          ),
        ],
      );
}

class _Tile<T> extends StatelessWidget {
  final String label;
  final ValueNotifier<T> n;
  final String Function(T) fmt;
  const _Tile(this.label, this.n, this.fmt);

  @override
  Widget build(BuildContext context) => Panel(
        child: Column(children: [
          ValueListenableBuilder<T>(
            valueListenable: n,
            builder: (_, v, __) => Text(fmt(v),
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: C.text)),
          ),
          Text(label, style: const TextStyle(color: C.muted, fontSize: 12)),
        ]),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CamState>(
        valueListenable: app.camera.state,
        builder: (_, s, __) {
          final (label, color) = switch (s) {
            CamState.streaming => ('Camera online', C.mint),
            CamState.connecting => ('Connecting', C.yellow),
            CamState.reconnecting => ('Reconnecting', C.yellow),
            CamState.offline => ('Camera offline', C.warn),
            CamState.idle => ('Not connected', C.muted),
          };
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: C.panel,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: C.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, size: 10, color: color),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          );
        },
      );
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CamState>(
        valueListenable: app.camera.state,
        builder: (_, s, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ValueListenableBuilder<String>(
              valueListenable: app.camera.message,
              builder: (_, m, __) => Text(
                switch (s) {
                  CamState.idle => 'Not connected.\nOpen the Connect tab.',
                  CamState.connecting => 'Connecting to camera...',
                  CamState.reconnecting => 'Reconnecting...\n$m',
                  CamState.offline => 'Camera offline.\n$m\nCheck Wi-Fi and the stream address.',
                  CamState.streaming => 'Waiting for first frame...',
                },
                textAlign: TextAlign.center,
                style: const TextStyle(color: C.muted),
              ),
            ),
          ),
        ),
      );
}
