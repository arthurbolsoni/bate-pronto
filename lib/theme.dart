import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFF0F1115);
  static const card = Color(0xFF181B22);
  static const line = Color(0xFF262B36);
  static const fg = Color(0xFFE6E9EF);
  static const mut = Color(0xFF8B93A7);
  static const acc = Color(0xFF4F8CFF);
  static const pos = Color(0xFF3ECF8E);
  static const neg = Color(0xFFFF6B6B);
  static const warn = Color(0xFFFFB454);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: C.acc,
      surface: C.card,
      error: C.neg,
    ),
    cardTheme: const CardThemeData(
      color: C.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: C.line),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: C.bg,
      foregroundColor: C.fg,
      elevation: 0,
      centerTitle: false,
    ),
    textTheme: base.textTheme.apply(bodyColor: C.fg, displayColor: C.fg),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.bg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: C.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: C.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: C.acc),
      ),
      labelStyle: const TextStyle(color: C.mut),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: C.acc,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
  );
}

/// Chip/pill reutilizável.
class Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const Pill(this.text, {super.key, this.bg = C.line, this.fg = C.mut});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 11, color: fg)),
      );
}
