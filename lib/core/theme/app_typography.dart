import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_colors.dart';

/// Mevora type scale.
///
/// Fraunces (a soft, warm serif) carries the human, editorial moments —
/// names, page headlines, the match moment. Manrope carries everything the
/// user reads to operate the app. Both ship as full Latin-Extended files so
/// Turkish glyphs (ğ ş İ) never fall back to a system font.
abstract final class AppTypography {
  static const String fontFamily = 'Manrope';
  static const String displayFontFamily = 'Fraunces';

  static TextTheme textTheme(MevoraPalette p) {
    TextStyle serif(double size, double height, {double tracking = -0.2}) =>
        TextStyle(
          fontFamily: displayFontFamily,
          fontSize: size,
          height: height / size,
          fontWeight: FontWeight.w600,
          letterSpacing: tracking,
          color: p.textPrimary,
        );
    TextStyle sans(
      double size,
      double height,
      FontWeight weight, {
      Color? color,
      double tracking = 0,
    }) => TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      letterSpacing: tracking,
      color: color ?? p.textPrimary,
    );

    return TextTheme(
      displayLarge: serif(44, 50, tracking: -0.8),
      displayMedium: serif(36, 42, tracking: -0.6),
      displaySmall: serif(32, 38, tracking: -0.4),
      headlineLarge: serif(30, 36, tracking: -0.4),
      headlineMedium: serif(26, 32, tracking: -0.3),
      headlineSmall: serif(22, 28),
      titleLarge: sans(20, 26, FontWeight.w700, tracking: -0.2),
      titleMedium: sans(17, 24, FontWeight.w600, tracking: -0.1),
      titleSmall: sans(15, 20, FontWeight.w600),
      bodyLarge: sans(16, 24, FontWeight.w400),
      bodyMedium: sans(15, 22, FontWeight.w400, color: p.textSecondary),
      bodySmall: sans(13, 18, FontWeight.w400, color: p.textTertiary),
      labelLarge: sans(15, 20, FontWeight.w600, tracking: 0.1),
      labelMedium: sans(13, 18, FontWeight.w600, color: p.textSecondary),
      labelSmall: sans(
        12,
        16,
        FontWeight.w600,
        color: p.textTertiary,
        tracking: 0.3,
      ),
    );
  }
}
