import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification.dart';
import 'package:mevora/l10n/app_localizations.dart';

class VerifiedProfileBadge extends StatelessWidget {
  const VerifiedProfileBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: theme.colorScheme.tertiary.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified,
            size: compact ? 14 : 16,
            color: theme.colorScheme.tertiary,
          ),
          const SizedBox(width: 4),
          Text(
            l10n.profileVerifiedBadge,
            style: (compact
                    ? theme.textTheme.labelSmall
                    : theme.textTheme.labelMedium)
                ?.copyWith(color: theme.colorScheme.tertiary),
          ),
        ],
      ),
    );
  }
}

String verificationEntryTitle(
  AppLocalizations l10n,
  IdentityVerificationStatus status, {
  required bool accountVerified,
}) {
  if (accountVerified || status == IdentityVerificationStatus.verified) {
    return l10n.profileVerified;
  }
  return switch (status) {
    IdentityVerificationStatus.pending ||
    IdentityVerificationStatus.inProgress =>
      l10n.verificationStarted,
    IdentityVerificationStatus.inReview => l10n.verificationInProgress,
    IdentityVerificationStatus.declined ||
    IdentityVerificationStatus.expired =>
      l10n.verificationCouldNotComplete,
    // `error` is a transient read/mapping problem, not a verdict. It offers
    // the same "verify your profile" affordance as a fresh start rather than
    // telling the user something failed that may not have.
    IdentityVerificationStatus.notStarted ||
    IdentityVerificationStatus.error ||
    IdentityVerificationStatus.verified =>
      l10n.verifyYourProfile,
  };
}

String? verificationEntrySubtitle(
  AppLocalizations l10n,
  IdentityVerificationStatus status, {
  required bool accountVerified,
}) {
  if (accountVerified || status == IdentityVerificationStatus.verified) {
    return null;
  }
  return switch (status) {
    IdentityVerificationStatus.notStarted ||
    IdentityVerificationStatus.error =>
      l10n.verificationDescription,
    IdentityVerificationStatus.pending ||
    IdentityVerificationStatus.inProgress ||
    IdentityVerificationStatus.inReview =>
      l10n.followVerificationInstructions,
    IdentityVerificationStatus.declined ||
    IdentityVerificationStatus.expired =>
      l10n.tryVerificationAgain,
    IdentityVerificationStatus.verified => null,
  };
}

IconData verificationEntryIcon(
  IdentityVerificationStatus status, {
  required bool accountVerified,
}) {
  if (accountVerified || status == IdentityVerificationStatus.verified) {
    return Icons.verified_outlined;
  }
  if (status.isInFlight) {
    return Icons.hourglass_top_outlined;
  }
  if (status == IdentityVerificationStatus.declined ||
      status == IdentityVerificationStatus.expired) {
    return Icons.error_outline;
  }
  return Icons.verified_user_outlined;
}
