import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/shared/animations/mevora_press_scale.dart';

/// A selectable choice (interests, filters, answers). For read-only labels
/// use [MevoraPill].
class MevoraChip extends StatelessWidget {
  const MevoraChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onSelected,
    this.avatar,
    this.compact = false,
    this.wrapLabel = false,
    this.onMedia = false,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  /// Leading widget — usually an [Icon].
  final Widget? avatar;
  final bool compact;

  /// When true, long labels wrap instead of ellipsizing to one line.
  final bool wrapLabel;

  /// Light-on-dark styling for use over photography.
  final bool onMedia;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = context.palette;

    final (Color bg, Color fg, Color line) = onMedia
        ? (
            selected ? AppColors.onMedia : AppColors.mediaControl,
            selected ? AppColors.ink : AppColors.onMedia,
            selected ? AppColors.onMedia : AppColors.mediaControlBorder,
          )
        : (
            selected ? scheme.primaryContainer : p.surface,
            selected ? scheme.onPrimaryContainer : p.textPrimary,
            selected ? scheme.primary : p.border,
          );

    final text = Text(
      label,
      maxLines: wrapLabel ? null : 1,
      overflow: wrapLabel ? TextOverflow.visible : TextOverflow.ellipsis,
      softWrap: true,
      style:
          (compact ? theme.textTheme.labelMedium : theme.textTheme.labelLarge)
              ?.copyWith(
                color: fg,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
    );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: wrapLabel
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        if (avatar != null) ...[
          IconTheme(
            data: IconThemeData(color: fg, size: compact ? 16 : 18),
            child: avatar!,
          ),
          const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
        ],
        Flexible(child: text),
      ],
    );

    final chip = AnimatedContainer(
      duration: AppDurations.fast,
      curve: AppCurves.standard,
      constraints: BoxConstraints(minHeight: compact ? 32 : 40),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.s12 : AppSpacing.md,
        vertical: compact ? AppSpacing.xs : AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(
          wrapLabel ? AppRadii.md : AppRadii.pill,
        ),
        border: Border.all(color: line, width: selected ? 1.5 : 1),
      ),
      child: wrapLabel
          ? ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width - 64,
              ),
              child: content,
            )
          : content,
    );

    if (onSelected == null) {
      return Semantics(label: label, selected: selected, child: chip);
    }
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: MevoraPressScale(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelected!(!selected),
          // Keep the visual compact but the hit area at the 48dp minimum.
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: compact ? AppSpacing.sm : AppSpacing.xs,
            ),
            child: chip,
          ),
        ),
      ),
    );
  }
}
