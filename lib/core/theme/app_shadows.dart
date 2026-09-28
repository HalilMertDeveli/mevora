import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_colors.dart';

/// Shadows are for things that float above the page — the Discover card, the
/// navigation bar, a sheet. Resting content uses surface colour for hierarchy.
abstract final class AppShadows {
  /// Barely-there lift for resting cards on the linen page.
  static List<BoxShadow> card(Brightness brightness) => [
    BoxShadow(
      color: AppColors.ink.withValues(
        alpha: brightness == Brightness.dark ? 0.3 : 0.04,
      ),
      blurRadius: 12,
      offset: const Offset(0, 2),
    ),
  ];

  /// Floating chrome: bottom navigation, floating action rows.
  static List<BoxShadow> floating(Brightness brightness) => [
    BoxShadow(
      color: AppColors.ink.withValues(
        alpha: brightness == Brightness.dark ? 0.4 : 0.08,
      ),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  /// The Discover card: one clear object on the page.
  static List<BoxShadow> discoveryCard(Brightness brightness) => [
    BoxShadow(
      color: AppColors.ink.withValues(
        alpha: brightness == Brightness.dark ? 0.4 : 0.10,
      ),
      blurRadius: 32,
      offset: const Offset(0, 12),
    ),
  ];
}
