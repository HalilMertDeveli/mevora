import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
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
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight - AppSpacing.screenPadding * 2,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const MevoraSpot(art: MevoraArt.location),
              const SizedBox(height: AppSpacing.lg),
              Semantics(
                header: true,
                child: Text(
                  l10n.locationPermissionTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              Text(
                l10n.locationPermissionMessage,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.locationPermissionSub,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xl),
              MevoraButton(
                label: l10n.useMyLocation,
                onPressed: isBusy ? null : onUseLocation,
                isLoading: isBusy,
              ),
              const SizedBox(height: AppSpacing.xs),
              MevoraButton(
                label: l10n.notNow,
                variant: MevoraButtonVariant.ghost,
                onPressed: isBusy ? null : onNotNow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
