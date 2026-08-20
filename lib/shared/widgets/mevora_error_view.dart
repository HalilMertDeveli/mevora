import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

class MevoraErrorView extends StatelessWidget {
  const MevoraErrorView({
    super.key,
    this.icon = Icons.error_outline_rounded,
    this.title,
    this.message,
    this.onRetry,
    this.retryLabel,
  });

  final IconData icon;
  final String? title;
  final String? message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final resolvedTitle = title ?? l10n?.somethingWentWrong ?? 'Something went wrong';
    final resolvedMessage =
        message ?? l10n?.unexpectedError ?? 'The app hit an unexpected error.';
    final resolvedRetry = retryLabel ?? l10n?.retry ?? 'Retry';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MevoraRiveAnimation(
                asset: MevoraRiveAssets.error,
                width: 72,
                height: 72,
                fallback: Icon(
                  icon,
                  size: 40,
                  color: theme.colorScheme.error,
                ),
              ),
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
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.lg),
                MevoraButton(
                  label: resolvedRetry,
                  onPressed: onRetry,
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
