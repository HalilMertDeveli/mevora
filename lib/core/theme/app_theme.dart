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
      inverseSurface: AppColors.card,
      onInverseSurface: AppColors.primaryText,
      inversePrimary: AppColors.accentPrimary,
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
      primary: AppColors.accentPrimary,
      onPrimary: AppColors.primaryText,
      primaryContainer: AppColors.deepWine,
      onPrimaryContainer: AppColors.accentPrimary,
      secondary: AppColors.accentSecondary,
      onSecondary: AppColors.primaryText,
      secondaryContainer: AppColors.darkBurgundy,
      onSecondaryContainer: AppColors.secondaryText,
      tertiary: AppColors.softPurple,
      onTertiary: AppColors.primaryText,
      tertiaryContainer: Color(0xFF2A1848),
      onTertiaryContainer: AppColors.softPurple,
      error: AppColors.error,
      onError: AppColors.primaryText,
      surface: AppColors.background,
      onSurface: AppColors.primaryText,
      onSurfaceVariant: AppColors.secondaryText,
      outline: AppColors.border,
      outlineVariant: Color(0x12FFFFFF),
      inverseSurface: AppColors.parchment,
      onInverseSurface: AppColors.ink,
      inversePrimary: AppColors.accentPrimary,
      surfaceContainerLowest: AppColors.primaryBackground,
      surfaceContainerLow: AppColors.card,
      surfaceContainer: AppColors.elevatedCard,
      surfaceContainerHigh: AppColors.secondaryCard,
      surfaceContainerHighest: AppColors.secondaryCard,
    ),
  );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
  }) {
    final isDark = brightness == Brightness.dark;
    final radii = BorderRadius.circular(AppRadii.md);
    final textTheme = AppTypography.textTheme(brightness);
    final navRadius = BorderRadius.circular(AppRadii.xl);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      fontFamily: AppTypography.fontFamily,
      scaffoldBackgroundColor: scheme.surface,
      disabledColor: isDark ? AppColors.mutedText : scheme.onSurface.withValues(alpha: 0.38),
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
        color: scheme.surfaceContainerLow,
        elevation: AppElevation.none,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: BorderSide(
            color: isDark ? AppColors.glassBorder : scheme.outlineVariant,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        selectedColor: scheme.primaryContainer,
        backgroundColor: scheme.surfaceContainer,
        labelStyle: textTheme.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        side: BorderSide(
          color: isDark ? AppColors.glassBorder : scheme.outlineVariant,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? scheme.surfaceContainer : scheme.surfaceContainerLowest,
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
          borderSide: BorderSide(
            color: isDark ? AppColors.glassBorder : scheme.outline,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radii,
          borderSide: BorderSide(
            color: isDark ? AppColors.glassBorder : scheme.outline,
          ),
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
          backgroundColor: isDark ? scheme.primary : null,
          foregroundColor: isDark ? scheme.onPrimary : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: isDark ? scheme.onSurface : scheme.primary,
          side: BorderSide(
            color: isDark ? AppColors.glassBorder : scheme.outline,
          ),
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
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? AppColors.glassFill : scheme.surfaceContainerLow,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
        elevation: AppElevation.none,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: scheme.primary, size: 24);
          }
          return IconThemeData(
            color: isDark ? AppColors.iconMuted : scheme.onSurfaceVariant,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return textTheme.labelSmall?.copyWith(color: scheme.primary);
          }
          return textTheme.labelSmall?.copyWith(
            color: isDark ? AppColors.iconMuted : scheme.onSurfaceVariant,
          );
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.elevatedCard : scheme.surfaceContainerLowest,
        elevation: AppElevation.medium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: isDark
              ? const BorderSide(color: AppColors.glassBorder)
              : BorderSide.none,
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.elevatedCard : scheme.surfaceContainerLowest,
        elevation: AppElevation.high,
        showDragHandle: true,
        dragHandleColor: isDark ? AppColors.iconMuted : scheme.outline,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
          side: isDark
              ? const BorderSide(color: AppColors.glassBorder)
              : BorderSide.none,
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
        color: isDark ? AppColors.glassBorder : scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        circularTrackColor: scheme.primaryContainer,
        linearTrackColor: scheme.primaryContainer,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: AppElevation.low,
        shape: RoundedRectangleBorder(
          borderRadius: navRadius,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? AppColors.elevatedCard : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: isDark
              ? const BorderSide(color: AppColors.glassBorder)
              : BorderSide.none,
        ),
      ),
    );
  }
}
