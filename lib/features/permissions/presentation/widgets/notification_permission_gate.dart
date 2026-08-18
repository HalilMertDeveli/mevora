import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/permission_scope.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/features/permissions/presentation/controllers/permission_controller.dart';
import 'package:mevora/features/permissions/presentation/pages/permission_prompt_page.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

/// Notifications feature entry. Does not request on first launch or page load.
class NotificationPermissionGate extends StatefulWidget {
  const NotificationPermissionGate({
    super.key,
    this.controller,
    this.child,
  });

  final PermissionController? controller;
  final Widget? child;

  @override
  State<NotificationPermissionGate> createState() =>
      _NotificationPermissionGateState();
}

class _NotificationPermissionGateState extends State<NotificationPermissionGate> {
  PermissionStatus _status = PermissionStatus.unknown;
  bool _loaded = false;

  PermissionController? get _controller =>
      widget.controller ?? PermissionScope.maybeOf(context)?.controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final status =
        await _controller?.check(PermissionType.notifications) ??
        PermissionStatus.unknown;
    if (mounted) {
      setState(() => _status = status);
    }
  }

  Future<void> _enable() async {
    await PermissionPromptPage.show(
      context,
      type: PermissionType.notifications,
      controller: _controller,
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_status.isUsable) {
      return widget.child ?? const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.permissionNotificationsDescription,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          MevoraButton(
            key: const Key('enable_notifications'),
            label: l10n.enableDeviceNotifications,
            onPressed: () => unawaited(_enable()),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.permissionContinueWithout,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
