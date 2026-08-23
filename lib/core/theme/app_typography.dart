import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_colors.dart';

/// Mevora type scale — Manrope for UI, Fraunces for display/brand moments.
abstract final class AppTypography {
  static const String fontFamily = 'Manrope';
  static const String displayFontFamily = 'Fraunces';

  static TextTheme textTheme(Brightness brightness) {
    final color = brightness == Brightness.dark
        ? AppColors.primaryText
        : AppColors.ink;
    final muted = brightness == Brightness.dark
        ? AppColors.secondaryText
        : AppColors.mutedInk;
    final subtle = brightness == Brightness.dark
        ? AppColors.mutedText
        : AppColors.mutedInk;

    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: displayFontFamily,
        fontSize: 40,
        fontWeight: FontWeight.w600,
        letterSpacing: 2.4,
        height: 1.1,
        color: color,
      ),
      displayMedium: TextStyle(
        fontFamily: displayFontFamily,
        fontSize: 34,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        height: 1.15,
        color: color,
      ),
      headlineMedium: TextStyle(
        fontFamily: displayFontFamily,
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.2,
        color: color,
      ),
      headlineSmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: color,
      ),
      titleLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: color,
      ),
      titleMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: color,
      ),
      titleSmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: color,
      ),
      bodyLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: color,
      ),
      bodyMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: muted,
      ),
      bodySmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: subtle,
      ),
      labelLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: color,
      ),
      labelMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: muted,
      ),
      labelSmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: subtle,
      ),
    );
  }
}
