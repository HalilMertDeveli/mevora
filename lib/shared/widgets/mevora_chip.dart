import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/shared/animations/mevora_press_scale.dart';

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
  final Widget? avatar;
  final bool compact;

  /// When true, long labels wrap instead of ellipsizing to one line.
  final bool wrapLabel;

  /// When true, force light-on-dark styling for photo overlays.
  final bool onMedia;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;

    late final Color bgColor;
    late final Color textColor;
    late final Border? border;

    if (onMedia) {
      bgColor = selected
          ? AppColors.accentPrimary.withValues(alpha: 0.85)
          : Colors.white.withValues(alpha: 0.14);
      textColor = AppColors.onMedia;
      border = selected
          ? null
          : Border.all(color: Colors.white.withValues(alpha: 0.28));
    } else {
      bgColor = selected
          ? colors.primary
          : (isDark ? Colors.transparent : Colors.transparent);
      textColor = selected
          ? colors.onPrimary
          : (isDark ? AppColors.primaryText : colors.onSurface);
      border = selected
          ? null
          : Border.all(
              color: isDark ? AppColors.glassBorder : colors.outline,
            );
    }

    final text = Text(
      label,
      maxLines: wrapLabel ? null : 1,
      overflow: wrapLabel ? TextOverflow.visible : TextOverflow.ellipsis,
      softWrap: true,
      style: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: textColor,
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
            data: IconThemeData(color: textColor, size: 18),
            child: avatar!,
          ),
          const SizedBox(width: 6),
        ],
        if (wrapLabel)
          Flexible(child: text)
        else
          Flexible(child: text),
      ],
    );

    final body = wrapLabel
        ? ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width - 64,
            ),
            child: content,
          )
        : content;

    return MevoraPressScale(
      enabled: onSelected != null,
      child: GestureDetector(
        onTap: onSelected != null ? () => onSelected!(!selected) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 6 : 10,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(
              wrapLabel ? AppRadii.md : AppRadii.pill,
            ),
            border: border,
          ),
          child: body,
        ),
      ),
    );
  }
}
