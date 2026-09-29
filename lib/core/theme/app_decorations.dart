import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_colors.dart';

/// Reusable decorations that are not simply a colour + radius.
abstract final class AppDecorations {
  /// Bottom scrim for text over photography. Transparent through the upper
  /// part of the image so the face stays untouched; dense only where text sits.
  static LinearGradient photoScrim({double strength = 1}) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.scrim.withValues(alpha: 0.18 * strength),
      AppColors.scrim.withValues(alpha: 0),
      AppColors.scrim.withValues(alpha: 0),
      AppColors.scrim.withValues(alpha: 0.55 * strength),
      AppColors.scrim.withValues(alpha: 0.82 * strength),
    ],
    stops: const [0, 0.18, 0.5, 0.78, 1],
  );
}
