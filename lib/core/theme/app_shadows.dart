import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_colors.dart';

abstract final class AppShadows {
  static List<BoxShadow> card(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return [
      BoxShadow(
        color: AppColors.ink.withValues(alpha: isDark ? 0.35 : 0.08),
        blurRadius: 24,
        offset: const Offset(0, 10),
      ),
    ];
  }
}
