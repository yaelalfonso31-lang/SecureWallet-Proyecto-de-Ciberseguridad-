import 'package:flutter/material.dart';

class AppTheme {
  static final ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6E4F)),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}
