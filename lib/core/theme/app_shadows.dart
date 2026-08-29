import 'package:flutter/material.dart';

abstract final class AppShadows {
  static List<BoxShadow> card(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return [
      BoxShadow(
        color: const Color(0xFF101828).withValues(alpha: isDark ? 0.35 : 0.06),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ];
  }

  static List<BoxShadow> discoveryCard(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return [
      BoxShadow(
        color: const Color(0xFF101828).withValues(alpha: isDark ? 0.35 : 0.08),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
    ];
  }
}
