import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/verification_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification.dart';
import 'package:mevora/features/verification/presentation/controllers/verification_controller.dart';
import 'package:mevora/features/verification/presentation/widgets/verified_profile_badge.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

class VerifyProfileScreen extends StatefulWidget {
  const VerifyProfileScreen({super.key});

  @override
  State<VerifyProfileScreen> createState() => _VerifyProfileScreenState();
}

class _VerifyProfileScreenState extends State<VerifyProfileScreen> {
  VerificationController? _controller;
  bool _started = false;

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
        appBar: AppBar(title: Text(l10n.verifyYourProfile)),
        body: MevoraLoading(message: l10n.loading),
      );
    }

    final status = controller.verification.status;
    final accountVerified = user?.isVerified == true || status.grantsVerifiedBadge;
    final busy = controller.phase != VerificationUiPhase.idle;
    final canStart = status.canStart && !accountVerified && !busy;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.verifyYourProfile)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          children: [
            if (accountVerified) ...[
              const Center(child: VerifiedProfileBadge()),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.profileVerified,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
            ] else ...[
              Text(
                l10n.verifyYourProfile,
                style: theme.textTheme.headlineSmall,
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
              if (status.isInFlight)
                MevoraCard(
                  emphasis: MevoraCardEmphasis.quiet,
                  child: Text(
                    l10n.verificationInProgress,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              if (status == IdentityVerificationStatus.declined ||
                  status == IdentityVerificationStatus.expired) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.verificationCouldNotComplete,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              if (controller.errorKey != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _errorMessage(l10n, controller.errorKey!),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              if (busy)
                MevoraLoading(
                  message: controller.phase == VerificationUiPhase.loadingToken
                      ? l10n.loading
                      : l10n.followVerificationInstructions,
                )
              else
                MevoraButton(
                  label: _primaryLabel(l10n, status),
                  icon: Icons.verified_user_outlined,
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

  String _primaryLabel(AppLocalizations l10n, IdentityVerificationStatus status) {
    if (status == IdentityVerificationStatus.declined ||
        status == IdentityVerificationStatus.expired) {
      return l10n.tryVerificationAgain;
    }
    return l10n.startVerification;
  }

  String _errorMessage(AppLocalizations l10n, String key) {
    return switch (key) {
      'verification-not-configured' => l10n.verificationNotConfigured,
      'verification-cooldown' => l10n.verificationCooldown,
      'verification-attempt-limit' => l10n.verificationAttemptLimit,
      'already-verified' => l10n.profileVerified,
      _ => l10n.verificationCouldNotComplete,
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
        Icon(Icons.check_circle_outline, color: theme.colorScheme.tertiary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
