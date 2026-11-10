import 'package:flutter/material.dart';

/// Tema global azul + amarillo (misma paleta que features/wallet/presentation/theme).
class AppTheme {
  static const Color _blue = Color(0xFF1B5FD0);
  static const Color _navy = Color(0xFF0B2A6B);
  static const Color _yellow = Color(0xFFFFC21A);
  static const Color _ink = Color(0xFF0F1F3D);
  static const Color _background = Color(0xFFF4F7FD);

  static final ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: _blue).copyWith(
      primary: _blue,
      onPrimary: Colors.white,
      secondary: _yellow,
      onSecondary: _ink,
    ),
    scaffoldBackgroundColor: _background,
    appBarTheme: const AppBarTheme(
      backgroundColor: _navy,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}
