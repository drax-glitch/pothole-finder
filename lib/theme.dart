import 'package:flutter/material.dart';

class C {
  static const asphalt = Color(0xFF1D222B);
  static const panel = Color(0xFF272D38);
  static const line = Color(0xFF3A4250);
  static const yellow = Color(0xFFFFC629);
  static const mint = Color(0xFF42E0C0);
  static const warn = Color(0xFFFF6A4D);
  static const text = Color(0xFFF2F0EA);
  static const muted = Color(0xFF9AA3B2);
}

ThemeData potTheme() {
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: C.asphalt,
    colorScheme: const ColorScheme.dark(
      primary: C.yellow,
      onPrimary: C.asphalt,
      secondary: C.mint,
      surface: C.panel,
      onSurface: C.text,
      error: C.warn,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: shape,
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: shape,
        foregroundColor: C.text,
        side: const BorderSide(color: C.line),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: C.panel,
      indicatorColor: Color(0x33FFC629),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.panel,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: C.line),
      ),
    ),
  );
}

/// Rounded panel used for cards and tiles.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? C.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: C.line),
        ),
        child: child,
      );
}
