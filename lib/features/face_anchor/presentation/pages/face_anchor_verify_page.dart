import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/face_anchor/domain/entities/face_anchor_state.dart';
import 'package:mevora/features/face_anchor/presentation/controllers/face_anchor_controller.dart';
import 'package:mevora/features/face_anchor/presentation/face_anchor_l10n.dart';
import 'package:mevora/features/face_anchor/presentation/widgets/face_anchor_badge.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_page_transitions.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_banner.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// Verifies one profile photo as the member: explains the check, takes the
/// member's agreement, then runs it.
///
/// The page reports what the server decided. It has no way to mark a photo
/// verified itself, and after a restart it is rebuilt from the server state
/// the controller follows.
class FaceAnchorVerifyPage extends StatefulWidget {
  const FaceAnchorVerifyPage({
    super.key,
    required this.photo,
    required this.controller,
  });

  final ProfilePhoto photo;
  final FaceAnchorController controller;

  /// Resolves to true when the photo was verified.
  static Future<bool> show(
    BuildContext context, {
    required ProfilePhoto photo,
    required FaceAnchorController controller,
  }) async {
    final verified = await Navigator.of(context).push<bool>(
      MevoraPageTransitions.route(
        builder: (_) =>
            FaceAnchorVerifyPage(photo: photo, controller: controller),
      ),
    );
    return verified ?? false;
  }

  @override
  State<FaceAnchorVerifyPage> createState() => _FaceAnchorVerifyPageState();
}

class _FaceAnchorVerifyPageState extends State<FaceAnchorVerifyPage> {
  bool _consent = false;
  FaceAnchorRunOutcome? _outcome;

  FaceAnchorController get _controller => widget.controller;

  Future<void> _run() async {
    setState(() => _outcome = null);
    final outcome = await _controller.verify(
      photoId: widget.photo.id,
      consentGiven: _consent,
    );
    if (!mounted) {
      return;
    }
    setState(() => _outcome = outcome);
  }

  /// Verified as the server sees it: by this run, or by a run whose answer
  /// arrived through the state stream after the app was reopened.
  bool get _verified {
    final state = _controller.state;
    return _outcome == FaceAnchorRunOutcome.verified ||
        (state.status == FaceAnchorStatus.verified &&
            state.photoId == widget.photo.id);
  }

  bool get _waiting {
    final state = _controller.state;
    return _controller.isBusy ||
        (state.isProcessing && state.photoId == widget.photo.id);
  }

  FaceAnchorReason? get _declinedReason {
    final state = _controller.state;
    if (state.didNotVerify && state.photoId == widget.photo.id) {
      return state.reason ?? FaceAnchorReason.technicalError;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return PopScope(
          // The selfie is on its way to the server; leaving now would only
          // hide the answer, not stop the check.
          canPop: !_controller.isBusy,
          child: Scaffold(
            appBar: AppBar(title: Text(l10n.faceAnchorVerifyAction)),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                children: [
                  _PhotoPreview(photo: widget.photo, verified: _verified),
                  const SizedBox(height: AppSpacing.lg),
                  ..._body(context, l10n),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _body(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    if (_verified) {
      return [
        MevoraBanner(
          title: l10n.faceAnchorVerified,
          message: l10n.faceAnchorSuccessBody,
          tone: MevoraTone.success,
          icon: MevoraIcons.faceAnchor,
        ),
        const SizedBox(height: AppSpacing.lg),
        MevoraButton(
          label: l10n.faceAnchorDone,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ];
    }
    if (_waiting) {
      return [
        const SizedBox(height: AppSpacing.lg),
        MevoraLoading(message: _progressLabel(l10n)),
      ];
    }

    final declined = _declinedReason;
    final errorKey = _controller.errorKey;
    return [
      Text(l10n.faceAnchorExplainBody, style: theme.textTheme.bodyLarge),
      const SizedBox(height: AppSpacing.sm),
      Text(
        l10n.faceAnchorExplainSteps,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: context.palette.textSecondary,
        ),
      ),
      if (declined != null) ...[
        const SizedBox(height: AppSpacing.md),
        MevoraBanner(
          title: l10n.faceAnchorNotVerified,
          message: FaceAnchorL10n.reason(l10n, declined),
          tone: MevoraTone.warning,
        ),
      ] else if (errorKey != null) ...[
        const SizedBox(height: AppSpacing.md),
        MevoraBanner(
          message: FaceAnchorL10n.error(l10n, errorKey),
          tone: MevoraTone.error,
        ),
      ],
      const SizedBox(height: AppSpacing.md),
      CheckboxListTile(
        key: const ValueKey('faceAnchorConsent'),
        value: _consent,
        onChanged: (value) => setState(() => _consent = value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.faceAnchorConsent, style: theme.textTheme.bodyMedium),
      ),
      const SizedBox(height: AppSpacing.md),
      MevoraButton(
        label: declined != null || errorKey != null
            ? l10n.faceAnchorRetry
            : l10n.faceAnchorTakeSelfie,
        icon: MevoraIcons.camera,
        onPressed: _consent ? () => unawaited(_run()) : null,
      ),
      if (declined != null) ...[
        const SizedBox(height: AppSpacing.sm),
        MevoraButton(
          label: l10n.faceAnchorChooseAnother,
          variant: MevoraButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    ];
  }

  String _progressLabel(AppLocalizations l10n) {
    return switch (_controller.phase) {
      FaceAnchorPhase.opening => l10n.faceAnchorOpening,
      FaceAnchorPhase.capturing => l10n.faceAnchorCapturing,
      FaceAnchorPhase.uploading => l10n.faceAnchorUploading,
      FaceAnchorPhase.verifying ||
      FaceAnchorPhase.idle => l10n.faceAnchorVerifying,
    };
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.photo, required this.verified});

  final ProfilePhoto photo;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final provider = MevoraNetworkImages.provider(photo.downloadUrl);
    final placeholder = ColoredBox(
      color: p.surfaceMuted,
      child: Icon(MevoraIcons.photo, color: p.textTertiary, size: 40),
    );
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: SizedBox(
          width: 180,
          height: 240,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (provider == null)
                placeholder
              else
                Image(
                  image: provider,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => placeholder,
                ),
              if (verified)
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: FaceAnchorBadge(dense: false),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
