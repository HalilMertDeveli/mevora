import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/shared/animations/mevora_press_scale.dart';

enum MevoraButtonVariant { primary, secondary, ghost, destructive }

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

  /// Default compact buttons keep 2 lines. Use [wrapLabel] for full answer text.
  final int? maxLines;

  /// When true, height grows with content and text is not ellipsized.
  final bool wrapLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final height = switch (size) {
      MevoraButtonSize.small => 40.0,
      MevoraButtonSize.medium => 52.0,
      MevoraButtonSize.large => 56.0,
    };
    final horizontalPadding = switch (size) {
      MevoraButtonSize.small => 14.0,
      MevoraButtonSize.medium => 18.0,
      MevoraButtonSize.large => 22.0,
    };
    final iconSize = switch (size) {
      MevoraButtonSize.small => 16.0,
      MevoraButtonSize.medium => 18.0,
      MevoraButtonSize.large => 20.0,
    };
    final enabled = onPressed != null && !isLoading;
    final resolvedMaxLines = wrapLabel ? null : maxLines;
    final child = AnimatedSwitcher(
      duration: AppDurations.short,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: isLoading
          ? SizedBox(
              key: const ValueKey('loading'),
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _foreground(colors),
              ),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: wrapLabel
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: iconSize),
                  const SizedBox(width: 8),
                ],
                if (isExpanded)
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: resolvedMaxLines,
                      overflow: wrapLabel
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                  )
                else
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: resolvedMaxLines,
                      overflow: wrapLabel
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                  ),
              ],
            ),
    );

    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(isExpanded ? double.infinity : 0, wrapLabel ? 0 : height),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: wrapLabel ? 14 : 8,
        ),
      ),
      elevation: const WidgetStatePropertyAll(0),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      visualDensity: wrapLabel ? VisualDensity.standard : null,
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: MevoraPressScale(
        enabled: enabled,
        child: switch (variant) {
          MevoraButtonVariant.primary => FilledButton(
            onPressed: enabled ? onPressed : null,
            style: style,
            child: child,
          ),
          MevoraButtonVariant.secondary => OutlinedButton(
            onPressed: enabled ? onPressed : null,
            style: style,
            child: child,
          ),
          MevoraButtonVariant.ghost => TextButton(
            onPressed: enabled ? onPressed : null,
            style: style,
            child: child,
          ),
          MevoraButtonVariant.destructive => FilledButton(
            onPressed: enabled ? onPressed : null,
            style: style.copyWith(
              backgroundColor: WidgetStatePropertyAll(colors.error),
              foregroundColor: WidgetStatePropertyAll(colors.onError),
            ),
            child: child,
          ),
        },
      ),
    );
  }

  Color _foreground(ColorScheme colors) {
    return switch (variant) {
      MevoraButtonVariant.primary => colors.onPrimary,
      MevoraButtonVariant.secondary => colors.primary,
      MevoraButtonVariant.ghost => colors.primary,
      MevoraButtonVariant.destructive => colors.onError,
    };
  }
}
