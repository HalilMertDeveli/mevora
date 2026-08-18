import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/di/permission_scope.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/features/permissions/domain/permission_flow_outcome.dart';
import 'package:mevora/features/permissions/presentation/controllers/permission_controller.dart';
import 'package:mevora/features/permissions/presentation/widgets/permission_denied_view.dart';
import 'package:mevora/features/permissions/presentation/widgets/permission_rationale_view.dart';
import 'package:mevora/l10n/app_localizations.dart';

enum _PromptPhase { rationale, denied, permanentlyDenied }

/// Design-system pre-prompt, then OS dialog. Never requests on page load.
class PermissionPromptPage extends StatefulWidget {
  const PermissionPromptPage({
    super.key,
    required this.type,
    this.mandatory = false,
    this.controller,
  });

  final PermissionType type;
  final bool mandatory;
  final PermissionController? controller;

  static Future<PermissionFlowOutcome> show(
    BuildContext context, {
    required PermissionType type,
    bool mandatory = false,
    PermissionController? controller,
  }) async {
    final result = await Navigator.of(context).push<PermissionFlowOutcome>(
      MaterialPageRoute(
        builder: (_) => PermissionPromptPage(
          type: type,
          mandatory: mandatory,
          controller: controller ?? PermissionScope.maybeOf(context)?.controller,
        ),
      ),
    );
    return result ?? PermissionFlowOutcome.skipped;
  }

  @override
  State<PermissionPromptPage> createState() => _PermissionPromptPageState();
}

class _PermissionPromptPageState extends State<PermissionPromptPage> {
  _PromptPhase _phase = _PromptPhase.rationale;

  PermissionController? get _controller =>
      widget.controller ?? PermissionScope.maybeOf(context)?.controller;

  Future<void> _allow() async {
    final controller = _controller;
    if (controller == null) {
      _finish(PermissionFlowOutcome.skipped);
      return;
    }
    final status = await controller.request(widget.type);
    if (!mounted) {
      return;
    }
    if (status.isUsable) {
      _finish(
        status.isLimited
            ? PermissionFlowOutcome.limited
            : PermissionFlowOutcome.granted,
      );
      return;
    }
    setState(() {
      _phase = status.isPermanentlyDenied
          ? _PromptPhase.permanentlyDenied
          : _PromptPhase.denied;
    });
  }

  Future<void> _openSettings() async {
    await _controller?.openSettings();
    if (!mounted) {
      return;
    }
    _finish(PermissionFlowOutcome.settingsOpened);
  }

  void _finish(PermissionFlowOutcome outcome) {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final l10n = AppLocalizations.of(context);
    Widget page = Scaffold(
      appBar: AppBar(title: Text(l10n.privacyPermissionsTitle)),
      body: SafeArea(child: _body(controller)),
    );
    if (controller != null) {
      page = ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Scaffold(
            appBar: AppBar(title: Text(l10n.privacyPermissionsTitle)),
            body: SafeArea(child: _body(controller)),
          );
        },
      );
    }
    return page;
  }

  Widget _body(PermissionController? controller) {
    final busy = controller?.isBusy ?? false;
    return switch (_phase) {
      _PromptPhase.rationale => PermissionRationaleView(
        type: widget.type,
        isBusy: busy,
        mandatory: widget.mandatory,
        onAllow: () => unawaited(_allow()),
        onSkip: widget.mandatory
            ? null
            : () => _finish(PermissionFlowOutcome.skipped),
      ),
      _PromptPhase.denied => PermissionDeniedView(
        type: widget.type,
        isBusy: busy,
        mandatory: widget.mandatory,
        onTryAgain: () => unawaited(_allow()),
        onContinueWithout: widget.mandatory
            ? null
            : () => _finish(PermissionFlowOutcome.denied),
      ),
      _PromptPhase.permanentlyDenied => PermissionDeniedView(
        type: widget.type,
        permanentlyDenied: true,
        isBusy: busy,
        mandatory: widget.mandatory,
        onOpenSettings: () => unawaited(_openSettings()),
        onContinueWithout: widget.mandatory
            ? null
            : () => _finish(PermissionFlowOutcome.denied),
      ),
    };
  }
}
