import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/location_scope.dart';
import 'package:mevora/features/location/domain/entities/location_screen_state.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

class LocationPermissionPage extends StatelessWidget {
  const LocationPermissionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = LocationScope.of(context).controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: AnimatedSwitcher(
                duration: AppDurations.short,
                child: KeyedSubtree(
                  key: ValueKey(controller.screen),
                  child: _body(context, controller.screen),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, LocationScreenState screen) {
    final controller = LocationScope.of(context).controller;
    final l10n = AppLocalizations.of(context);
    return switch (screen) {
      LocationScreenState.locating => _LoadingCopy(
        message: l10n.locationLocating,
      ),
      LocationScreenState.preparingMatches => _LoadingCopy(
        message: l10n.locationPreparingMatches,
      ),
      LocationScreenState.success ||
      LocationScreenState.reducedAccuracy => _StatusCopy(
        icon: Icons.check_circle_outline_rounded,
        title: l10n.locationSuccessTitle,
        message: screen == LocationScreenState.reducedAccuracy
            ? l10n.locationPreciseOffMessage
            : l10n.locationPermissionSub,
      ),
      LocationScreenState.serviceDisabled => _ActionCopy(
        icon: Icons.location_disabled_outlined,
        title: l10n.gpsDisabledTitle,
        message: l10n.gpsDisabledMessage,
        primaryLabel: l10n.openSettings,
        onPrimary: controller.isBusy
            ? null
            : () => unawaited(controller.openLocationSettings()),
        secondaryLabel: l10n.notNow,
        onSecondary: controller.isBusy
            ? null
            : () => unawaited(controller.skip()),
        hint: l10n.locationSkipHint,
      ),
      LocationScreenState.denied => _ActionCopy(
        icon: Icons.location_off_outlined,
        title: l10n.locationPermissionTitle,
        message: l10n.locationDeniedMessage,
        primaryLabel: l10n.useMyLocation,
        onPrimary: controller.isBusy
            ? null
            : () => unawaited(controller.retryDenied()),
        secondaryLabel: l10n.notNow,
        onSecondary: controller.isBusy
            ? null
            : () => unawaited(controller.skip()),
        hint: l10n.locationSkipHint,
        isPrimaryLoading: controller.isBusy,
      ),
      LocationScreenState.deniedForever ||
      LocationScreenState.restricted => _ActionCopy(
        icon: Icons.lock_outline_rounded,
        title: l10n.locationSettingsTitle,
        message: l10n.locationSettingsMessage,
        primaryLabel: l10n.openSettings,
        onPrimary: controller.isBusy
            ? null
            : () => unawaited(controller.openAppSettings()),
        secondaryLabel: l10n.notNow,
        onSecondary: controller.isBusy
            ? null
            : () => unawaited(controller.skip()),
        hint: l10n.locationSkipHint,
      ),
      LocationScreenState.error => _ActionCopy(
        icon: Icons.error_outline_rounded,
        title: l10n.locationUnavailableTitle,
        message: controller.errorMessage ?? l10n.locationTimeoutMessage,
        primaryLabel: l10n.tryAgain,
        onPrimary: controller.isBusy
            ? null
            : () => unawaited(controller.allow()),
        secondaryLabel: l10n.notNow,
        onSecondary: controller.isBusy
            ? null
            : () => unawaited(controller.skip()),
        hint: l10n.locationSkipHint,
        isPrimaryLoading: controller.isBusy,
      ),
      LocationScreenState.prompt => _ActionCopy(
        icon: Icons.explore_outlined,
        title: l10n.locationPermissionTitle,
        message: l10n.locationPermissionMessage,
        detail: l10n.locationPermissionSub,
        primaryLabel: l10n.useMyLocation,
        onPrimary: controller.isBusy
            ? null
            : () => unawaited(controller.allow()),
        secondaryLabel: l10n.notNow,
        onSecondary: controller.isBusy
            ? null
            : () => unawaited(controller.skip()),
        hint: l10n.locationSkipHint,
        isPrimaryLoading: controller.isBusy,
      ),
    };
  }
}

class _LoadingCopy extends StatelessWidget {
  const _LoadingCopy({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MevoraLoading.page(message: message);
  }
}

class _StatusCopy extends StatelessWidget {
  const _StatusCopy({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const Spacer(),
        Icon(icon, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: AppSpacing.lg),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const Spacer(),
      ],
    );
  }
}

class _ActionCopy extends StatelessWidget {
  const _ActionCopy({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.detail,
    this.secondaryLabel,
    this.onSecondary,
    this.hint,
    this.isPrimaryLoading = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? detail;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? hint;
  final bool isPrimaryLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const Spacer(),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Icon(icon, size: 40, color: theme.colorScheme.primary),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        if (detail != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            detail!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const Spacer(),
        MevoraButton(
          label: primaryLabel,
          onPressed: onPrimary,
          isLoading: isPrimaryLoading,
        ),
        if (secondaryLabel != null) ...[
          const SizedBox(height: AppSpacing.sm),
          MevoraButton(
            label: secondaryLabel!,
            onPressed: onSecondary,
            variant: MevoraButtonVariant.ghost,
          ),
        ],
        if (hint != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            hint!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
