import 'package:flutter/material.dart';

abstract final class AppShadows {
  static List<BoxShadow> card(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
        blurRadius: isDark ? 16 : 16,
        offset: Offset(0, isDark ? 6 : 6),
        spreadRadius: isDark ? 0 : -1,
      ),
    ];
  }

  static List<BoxShadow> discoveryCard(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
        blurRadius: isDark ? 28 : 20,
        offset: Offset(0, isDark ? 16 : 10),
      ),
    ];
  }
}
