import 'dart:io';
import 'package:flutter/material.dart';
import '../overlay.dart';
import '../state.dart';
import '../theme.dart';
import '../vision_math.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: app.historyVersion,
        builder: (_, __, ___) => FutureBuilder<List<Map<String, Object?>>>(
          future: app.db.all(),
          builder: (context, snap) {
            final rows = snap.data ?? [];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('History',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: C.yellow)),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(
                      child: Text('No potholes saved yet.\nStart detecting on the Live tab.',
                          textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
                    ),
                  ),
                for (final r in rows)
                  Dismissible(
                    key: ValueKey(r['id']),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: C.warn,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete),
                    ),
                    onDismissed: (_) => app.db.delete(r['id'] as int, r['image'] as String?),
                    child: _Item(r),
                  ),
              ],
            );
          },
        ),
      );
}

class _Item extends StatefulWidget {
  final Map<String, Object?> r;
  const _Item(this.r);
  @override
  State<_Item> createState() => _ItemState();
}

class _ItemState extends State<_Item> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final sev = r['severity'] as String;
    final fw = r['fw'] as int, fh = r['fh'] as int;
    final d = Detection((r['l'] as num).toDouble(), (r['t'] as num).toDouble(),
        (r['r'] as num).toDouble(), (r['b'] as num).toDouble(), (r['conf'] as num).toDouble(), 0);
    final time = DateTime.fromMillisecondsSinceEpoch(r['ts'] as int);
    final t = '${time.day}/${time.month} ${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => setState(() => _open = !_open),
        child: Panel(
          padding: EdgeInsets.zero,
          child: IntrinsicHeight(
            child: Row(children: [
              Container(
                width: 6,
                decoration: BoxDecoration(
                  color: severityColor(sev),
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(sev, style: TextStyle(fontWeight: FontWeight.w800, color: severityColor(sev))),
                      const Spacer(),
                      Text(t, style: const TextStyle(color: C.muted, fontSize: 12)),
                    ]),
                    Text('Confidence ${((d.conf) * 100).round()}%   Score ${(r['score'] as num).round()}/100',
                        style: const TextStyle(fontSize: 13)),
                    if (_open) ...[
                      const SizedBox(height: 10),
                      Text('Size: ${d.w.round()} x ${d.h.round()} px   Depth: not measured',
                          style: const TextStyle(color: C.muted, fontSize: 13)),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AspectRatio(
                          aspectRatio: fw / fh,
                          child: Stack(fit: StackFit.expand, children: [
                            Image.file(File(r['image'] as String), fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    const Center(child: Text('Image missing'))),
                            CustomPaint(painter: DetBoxPainter([d], fw, fh)),
                          ]),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
