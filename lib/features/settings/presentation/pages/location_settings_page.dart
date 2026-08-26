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

class LocationSettingsPage extends StatefulWidget {
  const LocationSettingsPage({super.key, this.controller});

  final PermissionController? controller;

  @override
  State<LocationSettingsPage> createState() => _LocationSettingsPageState();
}

class _LocationSettingsPageState extends State<LocationSettingsPage> {
  var _didBootstrap = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didBootstrap) {
      return;
    }
    _didBootstrap = true;
    final controller =
        widget.controller ?? PermissionScope.maybeOf(context)?.controller;
    if (controller != null) {
      unawaited(controller.check(PermissionType.location));
    }
  }

  PermissionController? get _controller =>
      widget.controller ?? PermissionScope.maybeOf(context)?.controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsLocation)),
      body: controller == null
          ? Center(child: Text(l10n.permissionStatusUnknown))
          : ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final status =
                    controller.statuses[PermissionType.location] ??
                    PermissionStatus.unknown;
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.screenPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        PermissionCopy.title(l10n, PermissionType.location),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(PermissionCopy.statusLabel(l10n, status)),
                      const SizedBox(height: AppSpacing.lg),
                      MevoraButton(
                        label: l10n.useMyLocation,
                        onPressed: () {
                          unawaited(
                            PermissionPromptPage.show(
                              context,
                              type: PermissionType.location,
                              controller: controller,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      MevoraButton(
                        label: l10n.openSettings,
                        variant: MevoraButtonVariant.secondary,
                        onPressed: () => unawaited(controller.openSettings()),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
