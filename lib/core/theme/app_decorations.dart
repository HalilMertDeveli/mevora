import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';

/// Reusable visual decorations for the Mevora dark theme.
abstract final class AppDecorations {
  static BoxDecoration glassCard({
    BorderRadius? borderRadius,
    Color? color,
  }) {
    return BoxDecoration(
      color: color ?? AppColors.glassFill,
      borderRadius: borderRadius ?? BorderRadius.circular(AppRadii.lg),
      border: Border.all(color: AppColors.glassBorder),
    );
  }

  static BoxDecoration ambientScreen({Color? base}) {
    final surface = base ?? AppColors.background;
    return BoxDecoration(
      color: surface,
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          AppColors.accentPrimary.withValues(alpha: 0.08),
          surface,
          AppColors.softPurple.withValues(alpha: 0.05),
        ],
        stops: const [0.0, 0.45, 1.0],
      ),
    );
  }

  static LinearGradient photoOverlayGradient({
    Color? base,
    List<double>? stops,
  }) {
    final b = base ?? AppColors.background;
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
