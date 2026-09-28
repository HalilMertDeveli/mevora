import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/verification_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification.dart';
import 'package:mevora/features/verification/presentation/controllers/verification_controller.dart';
import 'package:mevora/features/verification/presentation/widgets/verified_profile_badge.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';
import 'package:mevora/shared/widgets/mevora_banner.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
import 'package:mevora/shared/art/mevora_motion.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

class VerifyProfileScreen extends StatefulWidget {
  const VerifyProfileScreen({super.key});

  @override
  State<VerifyProfileScreen> createState() => _VerifyProfileScreenState();
}

class _VerifyProfileScreenState extends State<VerifyProfileScreen>
    with WidgetsBindingObserver {
  VerificationController? _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may have finished, cancelled, or been killed mid-flow. Whatever
    // happened, the backend is the only place that knows — so ask it rather
    // than inferring anything from the lifecycle event.
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller?.refresh() ?? Future<void>.value());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    final uid = AuthScope.maybeOf(context)?.user?.id;
    final repository = VerificationScope.maybeOf(context);
    if (uid == null || repository == null) {
      return;
    }
    _started = true;
    _controller = VerificationController(repository: repository, uid: uid)
      ..attach();
    _controller!.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final user = AuthScope.maybeOf(context)?.user;
    final controller = _controller;
    if (controller == null) {
      return Scaffold(
        appBar: AppBar(),
        body: MevoraLoading.page(message: l10n.loading),
      );
    }

    final status = controller.verification.status;
    final accountVerified =
        user?.isVerified == true || status.grantsVerifiedBadge;
    final busy = controller.isBusy;
    final retry = controller.verification.retryEligibility();
    final canStart = controller.canStart && !accountVerified;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          children: [
            if (accountVerified) ...[
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: MevoraSuccessMark(
                  size: 112,
                  color: context.palette.compatibility,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Center(child: VerifiedProfileBadge()),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.profileVerified,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineLarge,
              ),
            ] else ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: MevoraSpot(art: MevoraArt.verification, size: 88),
              ),
              const SizedBox(height: AppSpacing.md),
              Semantics(
                header: true,
                child: Text(
                  l10n.verifyYourProfile,
                  style: theme.textTheme.headlineLarge,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.verificationDescription,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              MevoraCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BenefitRow(text: l10n.verificationBenefitFakeProfiles),
                    const SizedBox(height: AppSpacing.sm),
                    _BenefitRow(text: l10n.verificationBenefitSpoofing),
                    const SizedBox(height: AppSpacing.sm),
                    _BenefitRow(text: l10n.verificationBenefitBadge),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (status.isInFlight || controller.awaitingReturn)
                MevoraBanner(
                  tone: MevoraTone.info,
                  icon: MevoraIcons.pending,
                  message: status == IdentityVerificationStatus.inReview
                      ? l10n.verificationUnderReview
                      : l10n.verificationProcessing,
                  actionLabel: l10n.verificationCheckAgain,
                  onAction: busy ? null : () => unawaited(controller.refresh()),
                ),
              if (status == IdentityVerificationStatus.declined ||
                  status == IdentityVerificationStatus.expired) ...[
                const SizedBox(height: AppSpacing.md),
                MevoraBanner(
                  tone: MevoraTone.warning,
                  message: status == IdentityVerificationStatus.expired
                      ? l10n.verificationExpired
                      : _declineMessage(l10n, controller.verification.reason),
                ),
              ],
              if (status == IdentityVerificationStatus.error) ...[
                const SizedBox(height: AppSpacing.md),
                MevoraBanner(
                  tone: MevoraTone.neutral,
                  message: l10n.verificationTemporaryError,
                ),
              ],
              if (!retry.allowed && retry.blockedBy != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _retryMessage(l10n, retry.blockedBy!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (controller.errorKey != null) ...[
                const SizedBox(height: AppSpacing.md),
                MevoraBanner(
                  tone: MevoraTone.error,
                  message: _errorMessage(l10n, controller.errorKey!),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              if (busy)
                MevoraLoading(
                  message: switch (controller.phase) {
                    VerificationUiPhase.creatingSession ||
                    VerificationUiPhase.refreshing => l10n.loading,
                    _ => l10n.followVerificationInstructions,
                  },
                )
              else
                MevoraButton(
                  label: _primaryLabel(l10n, status),
                  icon: MevoraIcons.safety,
                  size: MevoraButtonSize.large,
                  onPressed: canStart
                      ? () => unawaited(
                          controller.startVerification(
                            locale: Localizations.localeOf(context),
                          ),
                        )
                      : null,
                ),
            ],
            const SizedBox(height: AppSpacing.xl),
            MevoraCard(
              emphasis: MevoraCardEmphasis.quiet,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.verificationPrivacyNote,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: () => context.push(AppRoutes.legalPrivacy),
                    child: Text(l10n.privacyPolicy),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _primaryLabel(
    AppLocalizations l10n,
    IdentityVerificationStatus status,
  ) {
    if (status == IdentityVerificationStatus.declined ||
        status == IdentityVerificationStatus.expired) {
      return l10n.tryVerificationAgain;
    }
    return l10n.startVerification;
  }

  /// Maps a backend code to user-facing copy.
  ///
  /// Every unmapped key falls through to a generic message on purpose: a
  /// provider error string, a session id or a webhook state must never reach
  /// the screen.
  String _errorMessage(AppLocalizations l10n, String key) {
    return switch (key) {
      'verification-not-configured' => l10n.verificationNotConfigured,
      'verification-cooldown' => l10n.verificationCooldown,
      'verification-attempt-limit' => l10n.verificationAttemptLimit,
      'verification-in-progress' => l10n.verificationProcessing,
      'verification-unavailable' => l10n.verificationTemporaryError,
      'already-verified' => l10n.profileVerified,
      _ => l10n.verificationCouldNotComplete,
    };
  }

  /// What the user can do differently, by failed module. The provider's own
  /// wording about their document is never shown.
  String _declineMessage(
    AppLocalizations l10n,
    IdentityVerificationReason? reason,
  ) {
    return switch (reason) {
      IdentityVerificationReason.documentUnreadable ||
      IdentityVerificationReason.documentUnsupported =>
        l10n.verificationDeclinedDocument,
      IdentityVerificationReason.livenessFailed =>
        l10n.verificationDeclinedLiveness,
      IdentityVerificationReason.faceMismatch =>
        l10n.verificationDeclinedFaceMatch,
      IdentityVerificationReason.manualReview => l10n.verificationUnderReview,
      IdentityVerificationReason.providerError ||
      null => l10n.verificationCouldNotComplete,
    };
  }

  String _retryMessage(
    AppLocalizations l10n,
    IdentityVerificationRetryBlock block,
  ) {
    return switch (block) {
      IdentityVerificationRetryBlock.alreadyVerified => l10n.profileVerified,
      IdentityVerificationRetryBlock.inFlight => l10n.verificationProcessing,
      IdentityVerificationRetryBlock.cooldown => l10n.verificationCooldown,
      IdentityVerificationRetryBlock.dailyLimit =>
        l10n.verificationAttemptLimit,
    };
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          MevoraIcons.success,
          color: context.palette.compatibility,
          size: 20,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
