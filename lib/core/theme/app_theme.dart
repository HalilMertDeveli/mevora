import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_elevation.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/app_typography.dart';

/// Central Mevora theme. Screens must consume these tokens, not local palettes.
abstract final class AppTheme {
  static ThemeData light() => _build(
    brightness: Brightness.light,
    scheme: const ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.mulberry,
      onPrimary: Color(0xFFFFFBFF),
      primaryContainer: AppColors.mulberrySoft,
      onPrimaryContainer: AppColors.mulberryDark,
      secondary: AppColors.apricot,
      onSecondary: Color(0xFFFFFBFF),
      secondaryContainer: AppColors.apricotSoft,
      onSecondaryContainer: Color(0xFF4A2E12),
      tertiary: AppColors.moss,
      onTertiary: Color(0xFFFFFBFF),
      error: AppColors.danger,
      onError: Color(0xFFFFFBFF),
      surface: AppColors.parchment,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.mutedInk,
      outline: AppColors.outline,
      outlineVariant: Color(0xFFE8E0DB),
      inverseSurface: AppColors.nightSurface,
      onInverseSurface: Color(0xFFF4EEE8),
      inversePrimary: AppColors.blossom,
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF3EEEA),
      surfaceContainer: Color(0xFFEFE8E3),
      surfaceContainerHigh: Color(0xFFE9E1DC),
    ),
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    scheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.blossom,
      onPrimary: AppColors.mulberryDark,
      primaryContainer: Color(0xFF4A2454),
      onPrimaryContainer: AppColors.mulberrySoft,
      secondary: Color(0xFFE2A66A),
      onSecondary: Color(0xFF3B2410),
      secondaryContainer: Color(0xFF5A3B22),
      onSecondaryContainer: AppColors.apricotSoft,
      tertiary: Color(0xFF7FCBAD),
      onTertiary: Color(0xFF083828),
      error: Color(0xFFE08B8B),
      onError: Color(0xFF3B1010),
      surface: AppColors.night,
      onSurface: Color(0xFFF4EEE8),
      onSurfaceVariant: Color(0xFFB7AFC0),
      outline: Color(0xFF4A4250),
      outlineVariant: Color(0xFF352F3A),
      inverseSurface: AppColors.parchment,
      onInverseSurface: AppColors.ink,
      inversePrimary: AppColors.mulberry,
      surfaceContainerLowest: Color(0xFF100C12),
      surfaceContainerLow: AppColors.nightSurface,
      surfaceContainer: Color(0xFF261F2B),
      surfaceContainerHigh: Color(0xFF2E2634),
    ),
  );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
  }) {
    final radii = BorderRadius.circular(AppRadii.md);
    final textTheme = AppTypography.textTheme(brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      fontFamily: AppTypography.fontFamily,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: AppElevation.none,
        scrolledUnderElevation: AppElevation.low,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: AppElevation.none,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: ChipThemeData(
        selectedColor: scheme.primaryContainer,
        backgroundColor: scheme.surfaceContainer,
        labelStyle: textTheme.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: textTheme.bodyMedium,
        labelStyle: textTheme.bodyMedium,
        helperStyle: textTheme.bodySmall,
        errorStyle: textTheme.bodySmall?.copyWith(color: scheme.error),
        border: OutlineInputBorder(
          borderRadius: radii,
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radii,
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radii,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radii,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radii,
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: radii,
          borderSide: BorderSide(
            color: scheme.outline.withValues(alpha: 0.5),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          elevation: AppElevation.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        elevation: AppElevation.medium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        elevation: AppElevation.high,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.xl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        circularTrackColor: scheme.primaryContainer,
      ),
    );
  }
}
