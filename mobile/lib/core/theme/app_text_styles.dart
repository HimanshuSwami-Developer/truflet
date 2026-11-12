import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Inter body text.
TextStyle t(double size, {FontWeight w = FontWeight.w400, Color c = C.ink, double? h, double? ls, TextDecoration? deco}) =>
    GoogleFonts.inter(fontSize: size, fontWeight: w, color: c, height: h, letterSpacing: ls, decoration: deco);

/// Space Grotesk display text.
TextStyle d(double size, {FontWeight w = FontWeight.w700, Color c = C.ink, double? h, double? ls}) =>
    GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: w, color: c, height: h, letterSpacing: ls);
