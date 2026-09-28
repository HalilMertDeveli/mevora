import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/shared/animations/mevora_press_scale.dart';

/// Button hierarchy — one [primary] per view.
///
/// * [primary] — the one thing this screen is for (ember).
/// * [secondary] — a real alternative (outlined).
/// * [tonal] — a supporting action inside a card (sand fill).
/// * [ghost] — low emphasis: "Not now", "Skip", links.
/// * [inverse] — on the ink premium surface.
/// * [destructive] — irreversible actions only.
enum MevoraButtonVariant {
  primary,
  secondary,
  tonal,
  ghost,
  inverse,
  destructive,
}

enum MevoraButtonSize { small, medium, large }

class MevoraButton extends StatelessWidget {
  const MevoraButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = MevoraButtonVariant.primary,
    this.size = MevoraButtonSize.medium,
    this.isLoading = false,
    this.isExpanded = true,
    this.icon,
    this.maxLines = 2,
    this.wrapLabel = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final MevoraButtonVariant variant;
  final MevoraButtonSize size;
  final bool isLoading;
  final bool isExpanded;
  final IconData? icon;

  /// Default buttons keep 2 lines. Use [wrapLabel] for full answer text.
  final int? maxLines;

  /// When true, height grows with content and text is not ellipsized.
  final bool wrapLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = context.palette;
    final height = switch (size) {
      MevoraButtonSize.small => 40.0,
      MevoraButtonSize.medium => 52.0,
      MevoraButtonSize.large => 56.0,
    };
    final horizontalPadding = size == MevoraButtonSize.small
        ? AppSpacing.md
        : AppSpacing.lg;
    final iconSize = size == MevoraButtonSize.small ? 16.0 : 20.0;
    final textStyle = size == MevoraButtonSize.small
        ? theme.textTheme.labelMedium
        : theme.textTheme.labelLarge;

    final (Color bg, Color fg, BorderSide? side) = switch (variant) {
      MevoraButtonVariant.primary => (scheme.primary, scheme.onPrimary, null),
      MevoraButtonVariant.secondary => (
        p.surface,
        p.textPrimary,
        BorderSide(color: p.borderStrong),
      ),
      MevoraButtonVariant.tonal => (p.surfaceMuted, p.textPrimary, null),
      MevoraButtonVariant.ghost => (Colors.transparent, p.textPrimary, null),
      MevoraButtonVariant.inverse => (p.background, p.textPrimary, null),
      MevoraButtonVariant.destructive => (p.error, AppColors.paper, null),
    };

    final enabled = onPressed != null && !isLoading;
    final labelText = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: wrapLabel ? null : maxLines,
      overflow: wrapLabel ? TextOverflow.visible : TextOverflow.ellipsis,
      softWrap: true,
    );
    final child = AnimatedSwitcher(
      duration: AppDurations.fast,
      switchInCurve: AppCurves.enter,
      switchOutCurve: AppCurves.exit,
      child: isLoading
          ? SizedBox.square(
              key: const ValueKey('loading'),
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: iconSize),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Flexible(child: labelText),
              ],
            ),
    );

    bool disabled(Set<WidgetState> s) =>
        s.contains(WidgetState.disabled) && !isLoading;
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(isExpanded ? double.infinity : 64, wrapLabel ? 0 : height),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: wrapLabel ? AppSpacing.s12 : AppSpacing.sm,
        ),
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => disabled(s) && variant != MevoraButtonVariant.ghost
            ? p.surfaceMuted
            : bg,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => disabled(s) ? p.textTertiary : fg,
      ),
      overlayColor: WidgetStatePropertyAll(fg.withValues(alpha: 0.08)),
      side: side == null ? null : WidgetStatePropertyAll(side),
      elevation: const WidgetStatePropertyAll(0),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      textStyle: WidgetStatePropertyAll(textStyle),
      tapTargetSize: MaterialTapTargetSize.padded,
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: MevoraPressScale(
        enabled: enabled,
        child: TextButton(
          onPressed: enabled ? onPressed : null,
          style: style,
          child: child,
        ),
      ),
    );
  }
}
