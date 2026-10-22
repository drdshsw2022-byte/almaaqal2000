import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const night = Color(0xFF16183A);
  static const royal = Color(0xFF4338CA);
  static const violet = Color(0xFF7C3AED);
  static const cyan = Color(0xFF06B6D4);
  static const gold = Color(0xFFE2AA53);
  static const emerald = Color(0xFF10B981);
  static const rose = Color(0xFFF43F5E);
  static const orange = Color(0xFFF97316);
  static const bg = Color(0xFFF4F5FB);
  static const card = Colors.white;
  static const text = Color(0xFF1F2937);
  static const muted = Color(0xFF6B7280);

  static const mainGradient = LinearGradient(
    colors: [night, royal, violet],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  static const goldGradient = LinearGradient(
    colors: [Color(0xFFFBBF24), Color(0xFFF97316)],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  static LinearGradient grad(Color a, Color b) => LinearGradient(
      colors: [a, b], begin: Alignment.topRight, end: Alignment.bottomLeft);

  static final tilePalette = <LinearGradient>[
    grad(const Color(0xFF6366F1), const Color(0xFF8B5CF6)),
    grad(const Color(0xFF06B6D4), const Color(0xFF3B82F6)),
    grad(const Color(0xFF10B981), const Color(0xFF059669)),
    grad(const Color(0xFFF59E0B), const Color(0xFFF97316)),
    grad(const Color(0xFFEC4899), const Color(0xFFF43F5E)),
    grad(const Color(0xFF8B5CF6), const Color(0xFFD946EF)),
    grad(const Color(0xFF0EA5E9), const Color(0xFF6366F1)),
    grad(const Color(0xFF14B8A6), const Color(0xFF22C55E)),
  ];
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.royal,
      primary: AppColors.royal,
      secondary: AppColors.violet,
      tertiary: AppColors.gold,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: AppColors.bg,
  );
  final text = GoogleFonts.cairoTextTheme(base.textTheme).apply(
    bodyColor: AppColors.text,
    displayColor: AppColors.text,
  );
  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: GoogleFonts.cairo(
          fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    cardTheme: CardTheme(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF3F4FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE5E7F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.royal, width: 1.6),
      ),
      labelStyle: GoogleFonts.cairo(color: AppColors.muted),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.royal,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: Color(0xFFD7DAEA)),
        textStyle: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: GoogleFonts.cairo(fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentTextStyle: GoogleFonts.cairo(color: Colors.white),
    ),
    dialogTheme: DialogTheme(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
  );
}
