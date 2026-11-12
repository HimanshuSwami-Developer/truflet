import 'package:flutter/material.dart';

/// Design tokens from the Turflet design (light sporty palette).
class C {
  static const ink = Color(0xFF10231A);
  static const muted = Color(0xFF56695E);
  static const mutedInk = Color(0xFF3F5247);
  static const ground = Color(0xFFF5F8F3);
  static const line = Color(0xFFE3E9E1);
  static const divider = Color(0xFFEEF2EC);
  static const brand = Color(0xFF16803C);
  static const brandDark = Color(0xFF0F5E2C);
  static const green700 = Color(0xFF15803D);
  static const green900 = Color(0xFF14532D);
  static const lime = Color(0xFFB7F35A);
  static const limeSoft = Color(0xFFE3F7C8);
  static const mint = Color(0xFFDCFCE7);
  static const chip = Color(0xFFF1F4EF);
  static const segment = Color(0xFFE8EFE5);
  static const dashed = Color(0xFFD4DED0);
  static const radioOff = Color(0xFFA9BAAE);
  static const dotOff = Color(0xFFC8D3CB);
  static const blue = Color(0xFF1D4ED8);
  static const blueSoft = Color(0xFFDBEAFE);
  static const blueInk = Color(0xFF1E3A8A);
  static const purple = Color(0xFF6D28D9);
  static const purpleSoft = Color(0xFFEDE9FE);
  static const amber = Color(0xFF854D0E);
  static const amberSoft = Color(0xFFFEF3C7);
  static const teal = Color(0xFF0E7490);
  static const tealSoft = Color(0xFFCFFAFE);
  static const orange = Color(0xFFC2410C);
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
