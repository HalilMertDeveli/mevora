import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';

/// Heads a section of a page: title, optional supporting line, optional
/// trailing action ("Edit", "See all").
class MevoraSectionHeader extends StatelessWidget {
  const MevoraSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.icon,
    this.iconColor,
    this.actionLabel,
    this.onAction,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final String? subtitle;

  /// Small caps line above the title ("WHY YOU FIT").
  final String? eyebrow;
  final IconData? icon;
  final Color? iconColor;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (eyebrow != null) ...[
                    Text(
                      eyebrow!.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.1,
                        color: iconColor ?? p.textTertiary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  Row(
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 20, color: iconColor ?? p.textPrimary),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      Flexible(
                        child: Text(title, style: theme.textTheme.titleMedium),
                      ),
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(subtitle!, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}
