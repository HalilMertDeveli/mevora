import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/permission_scope.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/features/permissions/presentation/controllers/permission_controller.dart';
import 'package:mevora/features/permissions/presentation/pages/permission_prompt_page.dart';
import 'package:mevora/features/permissions/presentation/permission_copy.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

/// Settings → Privacy & Permissions. Checks status only; never requests on open.
class PrivacyPermissionsPage extends StatefulWidget {
  const PrivacyPermissionsPage({super.key, this.controller});

  final PermissionController? controller;

  @override
  State<PrivacyPermissionsPage> createState() => _PrivacyPermissionsPageState();
}

class _PrivacyPermissionsPageState extends State<PrivacyPermissionsPage> {
  var _checkedOnOpen = false;

  PermissionController? get _controller =>
      widget.controller ?? PermissionScope.maybeOf(context)?.controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checkedOnOpen) {
      return;
    }
    _checkedOnOpen = true;
    final controller = _controller;
    if (controller != null) {
      unawaited(controller.checkAll());
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.privacyPermissionsTitle)),
      body: controller == null
          ? const SizedBox.shrink()
          : ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                return ListView(
                  padding: const EdgeInsets.all(AppSpacing.screenPadding),
                  children: [
                    Text(
                      l10n.privacyPermissionsSubtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    for (final type in PermissionType.values)
                      _PermissionTile(
                        type: type,
                        status:
                            controller.statuses[type] ??
                            PermissionStatus.unknown,
                        onOpenPrompt: () => unawaited(_openPrompt(type)),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    MevoraButton(
                      label: l10n.privacyOpenDeviceSettings,
                      variant: MevoraButtonVariant.secondary,
                      onPressed: () => unawaited(controller.openSettings()),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Future<void> _openPrompt(PermissionType type) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    await PermissionPromptPage.show(
      context,
      type: type,
      controller: controller,
    );
    if (mounted) {
      await controller.check(type);
    }
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.type,
    required this.status,
    required this.onOpenPrompt,
  });

  final PermissionType type;
  final PermissionStatus status;
  final VoidCallback onOpenPrompt;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(PermissionCopy.icon(type)),
      title: Text(
        PermissionCopy.title(l10n, type),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(PermissionCopy.statusLabel(l10n, status)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onOpenPrompt,
    );
  }
}
