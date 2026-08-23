import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/verification/domain/entities/profile_verification.dart';
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
  ProfileVerificationStatus status, {
  required bool accountVerified,
}) {
  if (accountVerified || status == ProfileVerificationStatus.approved) {
    return l10n.profileVerified;
  }
  return switch (status) {
    ProfileVerificationStatus.started => l10n.verificationStarted,
    ProfileVerificationStatus.pending => l10n.verificationInProgress,
    ProfileVerificationStatus.rejected ||
    ProfileVerificationStatus.retryRequired =>
      l10n.verificationCouldNotComplete,
    ProfileVerificationStatus.notStarted ||
    ProfileVerificationStatus.approved =>
      l10n.verifyYourProfile,
  };
}

String? verificationEntrySubtitle(
  AppLocalizations l10n,
  ProfileVerificationStatus status, {
  required bool accountVerified,
}) {
  if (accountVerified || status == ProfileVerificationStatus.approved) {
    return null;
  }
  return switch (status) {
    ProfileVerificationStatus.notStarted => l10n.verificationDescription,
    ProfileVerificationStatus.started ||
    ProfileVerificationStatus.pending =>
      l10n.followVerificationInstructions,
    ProfileVerificationStatus.rejected ||
    ProfileVerificationStatus.retryRequired =>
      l10n.tryVerificationAgain,
    ProfileVerificationStatus.approved => null,
  };
}

IconData verificationEntryIcon(
  ProfileVerificationStatus status, {
  required bool accountVerified,
}) {
  if (accountVerified || status == ProfileVerificationStatus.approved) {
    return Icons.verified_outlined;
  }
  if (status.isInProgress) {
    return Icons.hourglass_top_outlined;
  }
  if (status == ProfileVerificationStatus.rejected ||
      status == ProfileVerificationStatus.retryRequired) {
    return Icons.error_outline;
  }
  return Icons.verified_user_outlined;
}
