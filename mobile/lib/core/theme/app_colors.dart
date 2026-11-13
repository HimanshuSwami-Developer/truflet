import 'package:flutter/material.dart';

/// Design tokens drawn from the Turflet logo: deep forest green wordmark, coral ball, warm paper ground.
class C {
  static const ink = Color(0xFF0C2419);
  static const muted = Color(0xFF5E6B63);
  static const mutedInk = Color(0xFF3D4B43);
  static const ground = Color(0xFFF7F5EF);
  static const line = Color(0xFFE5E2D8);
  static const divider = Color(0xFFEFECE4);
  static const brand = Color(0xFF143D2B);
  static const brandDark = Color(0xFF0B2A1D);
  static const green700 = Color(0xFF1F5A40);
  static const green900 = Color(0xFF0F3324);

  /// The logo's ball. Use for the single most important highlight on a screen.
  static const coral = Color(0xFFF2552C);
  static const coralSoft = Color(0xFFFFE8E0);
  static const lime = Color(0xFFFFDCCF);
  static const limeSoft = Color(0xFFE6EEE7);
  static const mint = Color(0xFFE9F0EA);
  static const chip = Color(0xFFF1EEE6);
  static const segment = Color(0xFFEAE7DE);
  static const dashed = Color(0xFFD8D4C8);
  static const radioOff = Color(0xFFAEB5AE);
  static const dotOff = Color(0xFFCCD0CA);
  static const blue = Color(0xFF1D4ED8);
  static const blueSoft = Color(0xFFDBEAFE);
  static const blueInk = Color(0xFF1E3A8A);
  static const purple = Color(0xFF6D28D9);
  static const purpleSoft = Color(0xFFEDE9FE);
  static const amber = Color(0xFF854D0E);
  static const amberSoft = Color(0xFFFEF3C7);
  static const teal = Color(0xFF0E7490);
  static const tealSoft = Color(0xFFCFFAFE);
  static const orange = Color(0xFFD9441F);
  static const orangeSoft = Color(0xFFFFEDD5);
  static const orangeInk = Color(0xFF9A3412);
  static const orangeDeep = Color(0xFF7C2D12);
  static const orangeBg = Color(0xFFFFF7ED);
  static const red = Color(0xFFDC2626);
  static const redInk = Color(0xFFB91C1C);
  static const redSoft = Color(0xFFFEE2E2);
  static const rose = Color(0xFFE11D48);
  static const roseSoft = Color(0xFFFFE4E6);
  static const warnBg = Color(0xFFFDF1E7);
  static const warnInk = Color(0xFF8A3C07);
  static const star = Color(0xFFEAB308);
}

Color hex(String? s, [Color fallback = C.brand]) {
  if (s == null || s.length < 7) return fallback;
  return Color(int.parse('FF${s.substring(1, 7)}', radix: 16));
}
