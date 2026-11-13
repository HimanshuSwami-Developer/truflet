import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

// One family across the app, echoing the Turflet wordmark: a heavy, tightly set geometric sans.

/// Body text.
TextStyle t(double size, {FontWeight w = FontWeight.w400, Color c = C.ink, double? h, double? ls, TextDecoration? deco}) =>
    GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: w, color: c, height: h, letterSpacing: ls, decoration: deco);

/// Display text: extra-bold and tightly tracked like the logo.
TextStyle d(double size, {FontWeight w = FontWeight.w800, Color c = C.ink, double? h, double? ls}) =>
    GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: w, color: c, height: h, letterSpacing: ls ?? -0.03 * size);
