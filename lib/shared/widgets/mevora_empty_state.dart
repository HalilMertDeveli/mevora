import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

class MevoraEmptyState extends StatelessWidget {
  const MevoraEmptyState({
    super.key,
    this.icon = Icons.hourglass_empty_rounded,
    this.riveAsset,
    this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final IconData icon;
  final String? riveAsset;
  final String? title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final resolvedTitle = title ?? l10n?.emptyTitle ?? 'Nothing here yet';
    final resolvedMessage =
        message ?? l10n?.emptyMessage ?? 'When there is something to show, it will appear here.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (riveAsset != null)
                MevoraRiveAnimation(
                  asset: riveAsset!,
                  width: 96,
                  height: 96,
                  fallback: Icon(
                    icon,
                    size: 40,
                    color: theme.colorScheme.primary,
                  ),
                )
              else
                Icon(icon, size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: AppSpacing.md),
              Text(
                resolvedTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                resolvedMessage,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.lg),
                MevoraButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  isExpanded: false,
                ),
              ],
              if (secondaryActionLabel != null && onSecondaryAction != null) ...[
                const SizedBox(height: AppSpacing.sm),
                MevoraButton(
                  label: secondaryActionLabel!,
                  onPressed: onSecondaryAction,
                  variant: MevoraButtonVariant.ghost,
                  isExpanded: false,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
