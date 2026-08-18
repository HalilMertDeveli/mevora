import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/features/permissions/presentation/permission_copy.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

/// Pre-prompt explanation. The OS dialog is shown only after the primary action.
class PermissionRationaleView extends StatelessWidget {
  const PermissionRationaleView({
    super.key,
    required this.type,
    this.onAllow,
    this.onSkip,
    this.isBusy = false,
    this.mandatory = false,
  });

  final PermissionType type;
  final VoidCallback? onAllow;
  final VoidCallback? onSkip;
  final bool isBusy;
  final bool mandatory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        children: [
          const Spacer(),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Icon(
                PermissionCopy.icon(type),
                size: 40,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            PermissionCopy.title(l10n, type),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            PermissionCopy.description(l10n, type),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const Spacer(),
          MevoraButton(
            label: l10n.permissionAllow,
            onPressed: isBusy ? null : onAllow,
            isLoading: isBusy,
          ),
          if (!mandatory && onSkip != null) ...[
            const SizedBox(height: AppSpacing.sm),
            MevoraButton(
              label: l10n.permissionContinueWithout,
              variant: MevoraButtonVariant.ghost,
              onPressed: isBusy ? null : onSkip,
            ),
          ],
        ],
      ),
    );
  }
}
