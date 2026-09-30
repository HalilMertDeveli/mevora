import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/app_operations_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';

/// Shown to everyone while the owner has the app in maintenance.
///
/// The server's message is plain text and replaces the default copy when
/// present. A signed-in member can still reach support and their account
/// (deletion, data export); the router keeps those routes open.
class MaintenancePage extends StatelessWidget {
  const MaintenancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final custom = AppOperationsScope.maybeOf(context)?.maintenanceMessage;
    final member = _isMember(AuthScope.maybeOf(context)?.status);
    return Scaffold(
      body: SafeArea(
        child: MevoraEmptyState(
          key: const Key('maintenancePage'),
          art: MevoraArt.generic,
          title: l10n.appOpsMaintenanceTitle,
          message: custom ?? l10n.appOpsMaintenanceMessage,
          actionLabel: member ? l10n.appOpsMaintenanceSupport : null,
          onAction: member
              ? () => _open(context, AppRoutes.supportCenter)
              : null,
          secondaryActionLabel: member ? l10n.appOpsMaintenanceAccount : null,
          onSecondaryAction: member
              ? () => _open(context, AppRoutes.accountSettings)
              : null,
        ),
      ),
    );
  }

  /// Support and account settings sit behind sign-in and onboarding; for
  /// anyone else the buttons would only bounce back here.
  static bool _isMember(Object? status) {
    return status is Authenticated &&
        (status.user.onboardingCompleted || status.user.profileCompleted);
  }

  static void _open(BuildContext context, String route) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      unawaited(router.push(route));
    }
  }
}
