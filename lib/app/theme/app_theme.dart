import 'package:flutter/material.dart';

class AppTheme {
  static const _seed = Color(0xFF1F4E79); // steel blue
  static const accent = Color(0xFFE07A1F); // engine orange

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, secondary: accent);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF5F6F8),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        centerTitle: false,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
      visualDensity: VisualDensity.standard,
    );
  }
}
