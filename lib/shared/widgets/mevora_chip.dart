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
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final Widget? avatar;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bgColor =
        selected ? (isDark ? AppColors.blossom : AppColors.mulberry) : Colors.transparent;
    final Color textColor = selected
        ? (isDark ? AppColors.ink : Colors.white)
        : (isDark ? const Color(0xFFF4EEE8) : AppColors.ink);
    final Border? border = selected
        ? null
        : Border.all(
            color: isDark ? const Color(0x55FFFFFF) : AppColors.outline,
          );

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
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: border,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (avatar != null) ...[
                IconTheme(
                  data: IconThemeData(color: textColor, size: 18),
                  child: avatar!,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
