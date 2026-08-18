import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/features/permissions/presentation/permission_copy.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

class PermissionDeniedView extends StatelessWidget {
  const PermissionDeniedView({
    super.key,
    required this.type,
    this.permanentlyDenied = false,
    this.onTryAgain,
    this.onOpenSettings,
    this.onContinueWithout,
    this.isBusy = false,
    this.mandatory = false,
  });

  final PermissionType type;
  final bool permanentlyDenied;
  final VoidCallback? onTryAgain;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onContinueWithout;
  final bool isBusy;
  final bool mandatory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final body = permanentlyDenied
        ? l10n.permissionPermanentlyDeniedBody
        : l10n.permissionDeniedBody;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        children: [
          const Spacer(),
          Icon(
            permanentlyDenied
                ? Icons.lock_outline_rounded
                : PermissionCopy.icon(type),
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.permissionDeniedTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            PermissionCopy.description(l10n, type),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const Spacer(),
          if (permanentlyDenied)
            MevoraButton(
              label: l10n.openSettings,
              onPressed: isBusy ? null : onOpenSettings,
              isLoading: isBusy,
            )
          else
            MevoraButton(
              label: l10n.tryAgain,
              onPressed: isBusy ? null : onTryAgain,
              isLoading: isBusy,
            ),
          if (!mandatory && onContinueWithout != null) ...[
            const SizedBox(height: AppSpacing.sm),
            MevoraButton(
              label: l10n.permissionContinueWithout,
              variant: MevoraButtonVariant.ghost,
              onPressed: isBusy ? null : onContinueWithout,
            ),
          ],
        ],
      ),
    );
  }
}
