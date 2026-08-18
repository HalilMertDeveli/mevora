import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/permission_scope.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/features/permissions/domain/permission_flow_outcome.dart';
import 'package:mevora/features/permissions/presentation/controllers/permission_controller.dart';
import 'package:mevora/features/permissions/presentation/pages/permission_prompt_page.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';

/// Add Photo entry: camera or gallery. Requests only the chosen source.
class AddPhotoPermissionPage extends StatefulWidget {
  const AddPhotoPermissionPage({super.key, this.controller});

  final PermissionController? controller;

  @override
  State<AddPhotoPermissionPage> createState() => _AddPhotoPermissionPageState();
}

class _AddPhotoPermissionPageState extends State<AddPhotoPermissionPage> {
  PermissionFlowOutcome? _lastOutcome;
  Object? _error;

  PermissionController? get _controller =>
      widget.controller ?? PermissionScope.maybeOf(context)?.controller;

  Future<void> _pick(PermissionType type) async {
    setState(() {
      _error = null;
    });
    try {
      final outcome = await PermissionPromptPage.show(
        context,
        type: type,
        controller: _controller,
      );
      if (mounted) {
        setState(() => _lastOutcome = outcome);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.onboardingAddPhoto)),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          children: [
            MevoraButton(
              key: const Key('add_photo_camera'),
              label: l10n.addPhotoCamera,
              icon: Icons.photo_camera_outlined,
              onPressed: () => unawaited(_pick(PermissionType.camera)),
            ),
            const SizedBox(height: AppSpacing.md),
            MevoraButton(
              key: const Key('add_photo_gallery'),
              label: l10n.addPhotoGallery,
              variant: MevoraButtonVariant.secondary,
              icon: Icons.photo_library_outlined,
              onPressed: () => unawaited(_pick(PermissionType.photos)),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_error != null)
              MevoraEmptyState(
                icon: Icons.error_outline,
                title: l10n.somethingWentWrong,
                message: l10n.permissionContinueWithout,
              )
            else if (_lastOutcome != null)
              Text(
                _outcomeLabel(l10n, _lastOutcome!),
                textAlign: TextAlign.center,
                key: const Key('add_photo_outcome'),
              ),
          ],
        ),
      ),
    );
  }

  String _outcomeLabel(
    AppLocalizations l10n,
    PermissionFlowOutcome outcome,
  ) {
    return switch (outcome) {
      PermissionFlowOutcome.granted || PermissionFlowOutcome.limited =>
        l10n.permissionStatusGranted,
      PermissionFlowOutcome.denied || PermissionFlowOutcome.skipped =>
        l10n.permissionContinueWithout,
      PermissionFlowOutcome.settingsOpened => l10n.openSettings,
    };
  }
}
