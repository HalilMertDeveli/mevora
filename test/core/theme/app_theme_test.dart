import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_elevation.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/core/theme/app_typography.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('light and dark themes carry the Mevora palette', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();

    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
    expect(light.colorScheme.primary, AppColors.ember);
    expect(light.scaffoldBackgroundColor, AppColors.linen);
    expect(light.colorScheme.onSurface, AppColors.ink);
    expect(light.colorScheme.tertiary, AppColors.sage);
    expect(light.extension<MevoraPalette>(), MevoraPalette.light);
    expect(dark.extension<MevoraPalette>(), MevoraPalette.dark);
    expect(light.appBarTheme.elevation, AppElevation.none);
    expect(light.filledButtonTheme.style?.elevation?.resolve({}), 0);
    expect(light.textTheme.titleLarge?.fontFamily, AppTypography.fontFamily);
    expect(
      light.textTheme.headlineLarge?.fontFamily,
      AppTypography.displayFontFamily,
    );
    final dialogShape = light.dialogTheme.shape! as RoundedRectangleBorder;
    expect(dialogShape.borderRadius, BorderRadius.circular(AppRadii.xl));
  });

  test('text and accent pairs meet WCAG AA', () {
    const p = MevoraPalette.light;
    expect(_contrast(p.textPrimary, p.background), greaterThanOrEqualTo(4.5));
    expect(_contrast(p.textSecondary, p.background), greaterThanOrEqualTo(4.5));
    expect(_contrast(p.textTertiary, p.background), greaterThanOrEqualTo(4.5));
    expect(_contrast(AppColors.paper, AppColors.ember), greaterThanOrEqualTo(4.5));
    expect(_contrast(p.compatibility, p.background), greaterThanOrEqualTo(4.5));
    expect(
      _contrast(p.onCompatibilityContainer, p.compatibilityContainer),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(p.onMusicContainer, p.musicContainer),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(p.onHumorContainer, p.humorContainer),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(p.onPremiumSurface, p.premiumSurface),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('typography, spacing and radius tokens stay centralized', () {
    expect(AppElevation.none, 0);
    expect(AppRadii.md, 14);
    expect(AppRadii.card, 24);
    expect(AppSpacing.minTouchTarget, 48);
    final theme = AppTypography.textTheme(MevoraPalette.light);
    expect(theme.bodySmall?.fontSize, 13);
    expect(theme.bodyLarge?.fontSize, 16);
    expect(theme.titleSmall?.fontWeight, FontWeight.w600);
  });
}
