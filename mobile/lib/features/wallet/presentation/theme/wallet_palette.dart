import 'package:flutter/material.dart';

/// Paleta azul + amarillo de SecureWallet.
class WalletColors {
  WalletColors._();

  static const Color navy = Color(0xFF0B2A6B);
  static const Color blue = Color(0xFF1B5FD0);
  static const Color sky = Color(0xFF4C8DF6);
  static const Color ice = Color(0xFFEAF2FF);
  static const Color background = Color(0xFFF4F7FD);

  static const Color yellow = Color(0xFFFFC21A);
  static const Color yellowDark = Color(0xFFE5A400);
  static const Color yellowSoft = Color(0xFFFFF4CC);

  static const Color ink = Color(0xFF0F1F3D);
  static const Color muted = Color(0xFF62708A);
  static const Color line = Color(0xFFE1E8F5);

  static const Color success = Color(0xFF1FA971);
  static const Color danger = Color(0xFFE04B4B);

  static const LinearGradient mainGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navy, blue],
  );
  static const LinearGradient skyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [blue, sky],
  );
  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ink, navy],
  );
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [yellow, Color(0xFFFFA000)],
  );

  static const List<BoxShadow> softShadow = [
    BoxShadow(color: Color(0x1A0B2A6B), blurRadius: 18, offset: Offset(0, 8)),
  ];
}

/// Estilos de texto reutilizables.
class WalletText {
  WalletText._();

  static const TextStyle h1 = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    color: WalletColors.ink,
    height: 1.15,
  );
  static const TextStyle h2 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: WalletColors.ink,
  );
  static const TextStyle h3 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: WalletColors.ink,
  );
  static const TextStyle body = TextStyle(
    fontSize: 14,
    color: WalletColors.ink,
    height: 1.35,
  );
  static const TextStyle muted = TextStyle(
    fontSize: 13,
    color: WalletColors.muted,
    height: 1.35,
  );
}
