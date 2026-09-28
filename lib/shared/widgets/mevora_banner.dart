import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// An inline message inside a page: a failed save, a pending review, an
/// encryption notice. Not a toast — it stays until the state changes.
class MevoraBanner extends StatelessWidget {
  const MevoraBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = MevoraTone.info,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.dismissTooltip,
  });

  final String message;
  final String? title;
  final MevoraTone tone;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;
  final String? dismissTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = mevoraToneColors(context, tone);
    final resolvedIcon =
        icon ??
        switch (tone) {
          MevoraTone.success => MevoraIcons.successOutline,
          MevoraTone.warning || MevoraTone.error => MevoraIcons.error,
          _ => MevoraIcons.info,
        };
    return Semantics(
      liveRegion: tone == MevoraTone.error,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.s12,
          AppSpacing.sm,
          AppSpacing.s12,
        ),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Icon(resolvedIcon, size: 20, color: c.strong),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(
                        title!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: c.fg,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                    ],
                    Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        height: 20 / 14,
                        color: c.fg,
                      ),
                    ),
                    if (actionLabel != null && onAction != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: TextButton(
                          onPressed: onAction,
                          style: TextButton.styleFrom(
                            foregroundColor: c.strong,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(48, 40),
                            alignment: Alignment.centerLeft,
                          ),
                          child: Text(actionLabel!),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                onPressed: onDismiss,
                tooltip:
                    dismissTooltip ??
                    MaterialLocalizations.of(context).closeButtonTooltip,
                icon: Icon(MevoraIcons.close, size: 18, color: c.fg),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}
