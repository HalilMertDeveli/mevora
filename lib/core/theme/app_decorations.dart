import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';

/// Reusable visual decorations for Mevora light and dark themes.
abstract final class AppDecorations {
  static BoxDecoration glassCard({
    Brightness brightness = Brightness.light,
    BorderRadius? borderRadius,
    Color? color,
  }) {
    final isDark = brightness == Brightness.dark;
    return BoxDecoration(
      color: color ??
          (isDark ? AppColors.glassFill : AppColors.lightGlassFill),
      borderRadius: borderRadius ?? BorderRadius.circular(AppRadii.lg),
      border: Border.all(
        color: isDark ? AppColors.glassBorder : AppColors.lightGlassBorder,
      ),
      boxShadow: isDark
          ? null
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
    );
  }

  static BoxDecoration ambientScreen({
    Brightness brightness = Brightness.light,
    Color? base,
  }) {
    final isDark = brightness == Brightness.dark;
    final surface = base ?? (isDark ? AppColors.background : AppColors.canvas);
    return BoxDecoration(
      color: surface,
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: isDark
            ? [
                AppColors.accentPrimary.withValues(alpha: 0.08),
                surface,
                AppColors.softPurple.withValues(alpha: 0.05),
              ]
            : [
                AppColors.rose.withValues(alpha: 0.05),
                surface,
                AppColors.peach.withValues(alpha: 0.04),
              ],
        stops: const [0.0, 0.45, 1.0],
      ),
    );
  }

  /// Overlay for photo cards / login hero. Always dark-based so white text stays legible.
  static LinearGradient photoOverlayGradient({
    Color? base,
    List<double>? stops,
    bool soft = false,
  }) {
    final b = base ?? AppColors.background;
    if (soft) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          b.withValues(alpha: 0.12),
          b.withValues(alpha: 0.0),
          b.withValues(alpha: 0.55),
          b.withValues(alpha: 0.82),
        ],
        stops: stops ?? const [0, 0.4, 0.72, 1],
      );
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        b.withValues(alpha: 0.2),
        b.withValues(alpha: 0.0),
        b.withValues(alpha: 0.8),
        b.withValues(alpha: 0.95),
      ],
      stops: stops ?? const [0, 0.38, 0.72, 1],
    );
  }
}
