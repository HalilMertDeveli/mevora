import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

/// Shown before the native GPS prompt. Never shown automatically at app start.
class LocationPermissionScreen extends StatelessWidget {
  const LocationPermissionScreen({
    super.key,
    this.onUseLocation,
    this.onNotNow,
    this.isBusy = false,
  });

  final VoidCallback? onUseLocation;
  final VoidCallback? onNotNow;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.place_outlined,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.locationPermissionTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.locationPermissionMessage,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.locationPermissionSub,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),
          MevoraButton(
            label: l10n.useMyLocation,
            onPressed: isBusy ? null : onUseLocation,
            isLoading: isBusy,
          ),
          const SizedBox(height: AppSpacing.sm),
          MevoraButton(
            label: l10n.notNow,
            variant: MevoraButtonVariant.ghost,
            onPressed: isBusy ? null : onNotNow,
          ),
        ],
      ),
    );
  }
}
