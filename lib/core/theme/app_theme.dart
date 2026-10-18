import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const teal = Color(0xFF018786);
  static const orange = Color(0xFFFE9402);

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: teal, brightness: Brightness.dark,
      primary: const Color(0xFF03DAC6), onPrimary: Colors.black,
      surface: const Color(0xFF181818),
    );
    return ThemeData(
      brightness: Brightness.dark, colorScheme: scheme, useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF101010),
      focusColor: orange.withValues(alpha: .55),
      iconButtonTheme: IconButtonThemeData(style: ButtonStyle(
        overlayColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.focused) ? orange.withValues(alpha: .7) : null),
      )),
      appBarTheme: const AppBarThemeData(backgroundColor: Color(0xFF101010),
        surfaceTintColor: Colors.transparent, elevation: 0),
      cardTheme: const CardThemeData(margin: EdgeInsets.zero, elevation: 0),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true, fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: orange, width: 2)),
      ),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    );
  }
}
