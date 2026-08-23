import 'package:flutter/material.dart';

abstract final class AppShadows {
  static List<BoxShadow> card(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
        blurRadius: isDark ? 16 : 24,
        offset: Offset(0, isDark ? 6 : 10),
      ),
    ];
  }
}
