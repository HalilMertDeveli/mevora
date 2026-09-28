import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_elevation.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/app_typography.dart';

/// Central Mevora theme. Screens consume these roles — never local palettes.
///
/// Material components are restyled here once, so a plain `FilledButton`,
/// `Switch` or `showModalBottomSheet` already looks like Mevora.
abstract final class AppTheme {
  static ThemeData light() => _build(
    palette: MevoraPalette.light,
    scheme: const ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.ember,
      onPrimary: AppColors.paper,
      primaryContainer: AppColors.emberSoft,
      onPrimaryContainer: AppColors.emberInk,
      secondary: AppColors.ink,
      onSecondary: AppColors.linen,
      secondaryContainer: AppColors.sand,
      onSecondaryContainer: AppColors.ink,
      tertiary: AppColors.sage,
      onTertiary: AppColors.paper,
      tertiaryContainer: AppColors.sageSoft,
      onTertiaryContainer: AppColors.sageInk,
      error: AppColors.error,
      onError: AppColors.paper,
      errorContainer: AppColors.errorSoft,
      onErrorContainer: Color(0xFF6B1712),
      surface: AppColors.linen,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.ink60,
      outline: AppColors.stoneDeep,
      outlineVariant: AppColors.stone,
      shadow: AppColors.ink,
      scrim: AppColors.scrim,
      inverseSurface: AppColors.ink,
      onInverseSurface: AppColors.linen,
      inversePrimary: AppColors.emberNight,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: AppColors.paper,
      surfaceContainerLow: AppColors.paper,
      surfaceContainer: AppColors.sand,
      surfaceContainerHigh: AppColors.sand,
      surfaceContainerHighest: AppColors.sandDeep,
    ),
  );

  static ThemeData dark() => _build(
    palette: MevoraPalette.dark,
    scheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.emberNight,
      onPrimary: AppColors.night,
      primaryContainer: Color(0xFF4A2219),
      onPrimaryContainer: Color(0xFFFBD5CA),
      secondary: AppColors.nightInk,
      onSecondary: AppColors.night,
      secondaryContainer: AppColors.nightMuted,
      onSecondaryContainer: AppColors.nightInk,
      tertiary: Color(0xFF6FB8A7),
      onTertiary: AppColors.night,
      tertiaryContainer: Color(0xFF1A322C),
      onTertiaryContainer: Color(0xFFCBE8DF),
      error: Color(0xFFEF7A72),
      onError: AppColors.night,
      errorContainer: Color(0xFF3D1B19),
      onErrorContainer: Color(0xFFFBD3CF),
      surface: AppColors.night,
      onSurface: AppColors.nightInk,
      onSurfaceVariant: AppColors.nightInkMuted,
      outline: Color(0xFF4A4550),
      outlineVariant: AppColors.nightBorder,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: AppColors.linen,
      onInverseSurface: AppColors.ink,
      inversePrimary: AppColors.ember,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: AppColors.night,
      surfaceContainerLow: AppColors.nightSurface,
      surfaceContainer: AppColors.nightMuted,
      surfaceContainerHigh: AppColors.nightElevated,
      surfaceContainerHighest: AppColors.nightMuted,
    ),
  );

  static ThemeData _build({
    required MevoraPalette palette,
    required ColorScheme scheme,
  }) {
    final textTheme = AppTypography.textTheme(palette);
    final controlRadius = BorderRadius.circular(AppRadii.md);
    const pill = StadiumBorder();
    const buttonHeight = 52.0;

    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: controlRadius,
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      extensions: [palette],
      textTheme: textTheme,
      fontFamily: AppTypography.fontFamily,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      dividerColor: palette.divider,
      disabledColor: palette.textTertiary.withValues(alpha: 0.6),
      splashFactory: InkSparkle.splashFactory,
      highlightColor: Colors.transparent,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      iconTheme: IconThemeData(color: palette.textPrimary, size: 24),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.none,
        scrolledUnderElevation: AppElevation.none,
        centerTitle: false,
        titleSpacing: AppSpacing.screenPadding,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: palette.textPrimary, size: 24),
        actionsIconTheme: IconThemeData(color: palette.textPrimary, size: 24),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.none,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: BorderSide(color: palette.border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        minVerticalPadding: AppSpacing.s12,
        horizontalTitleGap: AppSpacing.s12,
        iconColor: palette.textSecondary,
        textColor: palette.textPrimary,
        titleTextStyle: textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: controlRadius),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surface,
        selectedColor: scheme.primaryContainer,
        disabledColor: palette.surfaceMuted,
        labelStyle: textTheme.labelMedium?.copyWith(color: palette.textPrimary),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onPrimaryContainer,
        ),
        side: BorderSide(color: palette.border),
        shape: pill,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: textTheme.bodyLarge?.copyWith(color: palette.textTertiary),
        labelStyle: textTheme.bodyLarge?.copyWith(color: palette.textSecondary),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        helperStyle: textTheme.bodySmall,
        errorStyle: textTheme.bodySmall?.copyWith(color: palette.error),
        prefixIconColor: palette.textSecondary,
        suffixIconColor: palette.textSecondary,
        border: inputBorder(palette.border),
        enabledBorder: inputBorder(palette.border),
        focusedBorder: inputBorder(scheme.primary, 1.5),
        errorBorder: inputBorder(palette.error),
        focusedErrorBorder: inputBorder(palette.error, 1.5),
        disabledBorder: inputBorder(palette.divider),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, buttonHeight),
          elevation: AppElevation.none,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: palette.surfaceMuted,
          disabledForegroundColor: palette.textTertiary,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: pill,
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, buttonHeight),
          elevation: AppElevation.none,
          backgroundColor: palette.surface,
          foregroundColor: palette.textPrimary,
          shape: pill,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, buttonHeight),
          foregroundColor: palette.textPrimary,
          backgroundColor: palette.surface,
          disabledForegroundColor: palette.textTertiary,
          side: BorderSide(color: palette.borderStrong),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: pill,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: palette.textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: pill,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: palette.textPrimary,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: AppElevation.low,
        shape: const StadiumBorder(),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: palette.surface,
          foregroundColor: palette.textSecondary,
          selectedBackgroundColor: palette.textPrimary,
          selectedForegroundColor: palette.background,
          side: BorderSide(color: palette.border),
          textStyle: textTheme.labelMedium,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return palette.surfaceMuted;
          }
          return AppColors.paper;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return states.contains(WidgetState.disabled)
                ? scheme.primary.withValues(alpha: 0.4)
                : scheme.primary;
          }
          return palette.borderStrong;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        thumbIcon: const WidgetStatePropertyAll(null),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
        side: BorderSide(color: palette.borderStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : palette.borderStrong,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: palette.surfaceMuted,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        trackHeight: 4,
        valueIndicatorColor: palette.textPrimary,
        valueIndicatorTextStyle: textTheme.labelMedium?.copyWith(
          color: palette.background,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: const StadiumBorder(),
        elevation: AppElevation.none,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : palette.textSecondary,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            letterSpacing: 0.1,
            color: selected ? palette.textPrimary : palette.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          );
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: palette.textPrimary,
        unselectedLabelColor: palette.textSecondary,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
        indicatorColor: scheme.primary,
        dividerColor: palette.divider,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.high,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xl),
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: palette.surface,
        elevation: AppElevation.high,
        modalElevation: AppElevation.high,
        showDragHandle: true,
        dragHandleColor: palette.borderStrong,
        dragHandleSize: const Size(36, 4),
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.xl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        actionTextColor: scheme.inversePrimary,
        elevation: AppElevation.medium,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: controlRadius),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        textStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: palette.divider,
        space: 1,
        thickness: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        circularTrackColor: Colors.transparent,
        linearTrackColor: palette.surfaceMuted,
        linearMinHeight: 4,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.high,
        textStyle: textTheme.bodyLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        headerHeadlineStyle: textTheme.headlineMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xl),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
