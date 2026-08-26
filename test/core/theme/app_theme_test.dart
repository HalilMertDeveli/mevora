import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_elevation.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/core/theme/app_typography.dart';

void main() {
  test('light and dark themes use Mevora brand colors', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();

    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
    expect(light.colorScheme.primary, AppColors.rose);
    expect(light.colorScheme.surface, AppColors.canvas);
    expect(light.scaffoldBackgroundColor, AppColors.canvas);
    expect(dark.colorScheme.primary, AppColors.blossom);
    expect(light.colorScheme.secondary, AppColors.peach);
    expect(light.colorScheme.tertiary, AppColors.moss);
    expect(light.appBarTheme.elevation, AppElevation.none);
    expect(light.filledButtonTheme.style?.elevation?.resolve({}), 0);
    expect(light.textTheme.titleLarge?.fontFamily, AppTypography.fontFamily);
    expect(light.dialogTheme.shape, isA<RoundedRectangleBorder>());
    final dialogShape = light.dialogTheme.shape! as RoundedRectangleBorder;
    expect(dialogShape.borderRadius, BorderRadius.circular(AppRadii.lg));
  });

  test('typography and elevation tokens stay centralized', () {
    expect(AppElevation.none, 0);
    expect(AppElevation.high, 4);
    expect(AppRadii.md, 14);
    final theme = AppTypography.textTheme(Brightness.light);
    expect(theme.bodySmall?.fontSize, 12);
    expect(theme.titleSmall?.fontWeight, FontWeight.w600);
  });
}
