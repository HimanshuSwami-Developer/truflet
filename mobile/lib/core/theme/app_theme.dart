import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: C.brand, primary: C.brand, secondary: C.coral, surface: Colors.white),
  );
  return base.copyWith(
    scaffoldBackgroundColor: C.ground,
    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(bodyColor: C.ink, displayColor: C.ink),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: C.brand, selectionHandleColor: C.coral),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: C.brand),
    splashFactory: InkRipple.splashFactory,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.ink,
      contentTextStyle: t(14, c: Colors.white, w: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
