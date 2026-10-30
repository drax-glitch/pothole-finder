import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/connect.dart';
import 'screens/history.dart';
import 'screens/live.dart';
import 'screens/settings.dart';
import 'state.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const PotFinderApp());
}

class PotFinderApp extends StatelessWidget {
  const PotFinderApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'PotFinder',
        debugShowCheckedModeBanner: false,
        theme: potTheme(),
        home: const Splash(),
      );
}

class Splash extends StatefulWidget {
  const Splash({super.key});
  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void initState() {
    super.initState();
    Future.wait([app.init(), Future<void>.delayed(const Duration(milliseconds: 2400))]).then((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => const Shell(),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ));
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 200,
              height: 200,
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) => CustomPaint(painter: _RingsPainter(_c.value)),
              ),
            ),
            const SizedBox(height: 12),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              builder: (_, v, child) => Opacity(
                opacity: v,
                child: Transform.translate(offset: Offset(0, 20 * (1 - v)), child: child),
              ),
              child: const Text('PotFinder',
                  style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: C.yellow)),
            ),
            const SizedBox(height: 8),
            const Text('Find the potholes before they find you.',
                style: TextStyle(color: C.muted, fontSize: 14)),
          ]),
        ),
      );
}

class _RingsPainter extends CustomPainter {
  final double t;
  _RingsPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final v = (t + i / 3) % 1;
      canvas.drawCircle(
        c,
        30 + 70 * v,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = C.yellow.withAlpha((255 * (1 - v)).round()),
      );
    }
    canvas.drawOval(Rect.fromCenter(center: c, width: 64, height: 34), Paint()..color = const Color(0xFF0F1217));
  }

  @override
  bool shouldRepaint(_RingsPainter o) => o.t != t;
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: IndexedStack(index: _i, children: const [
            LiveScreen(),
            ConnectScreen(),
            HistoryScreen(),
            SettingsScreen(),
          ]),
        ),
        bottomNavigationBar: ValueListenableBuilder<int>(
          valueListenable: app.newHistory,
          builder: (_, n, __) => NavigationBar(
            selectedIndex: _i,
            onDestinationSelected: (i) {
              setState(() => _i = i);
              if (i == 2) app.newHistory.value = 0;
            },
            destinations: [
              const NavigationDestination(icon: Icon(Icons.videocam_outlined), label: 'Live'),
              const NavigationDestination(icon: Icon(Icons.wifi), label: 'Connect'),
              NavigationDestination(
                icon: Badge(isLabelVisible: n > 0, label: Text('$n'), child: const Icon(Icons.history)),
                label: 'History',
              ),
              const NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
            ],
          ),
        ),
      );
}
