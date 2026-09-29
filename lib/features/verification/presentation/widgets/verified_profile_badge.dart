import 'package:flutter/material.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

class VerifiedProfileBadge extends StatelessWidget {
  const VerifiedProfileBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return MevoraPill(
      label: AppLocalizations.of(context).profileVerifiedBadge,
      icon: MevoraIcons.verified,
      tone: MevoraTone.compatibility,
      dense: compact,
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
    IdentityVerificationStatus.inProgress => l10n.verificationStarted,
    IdentityVerificationStatus.inReview => l10n.verificationInProgress,
    IdentityVerificationStatus.declined ||
    IdentityVerificationStatus.expired => l10n.verificationCouldNotComplete,
    // `error` is a transient read/mapping problem, not a verdict. It offers
    // the same "verify your profile" affordance as a fresh start rather than
    // telling the user something failed that may not have.
    IdentityVerificationStatus.notStarted ||
    IdentityVerificationStatus.error ||
    IdentityVerificationStatus.verified => l10n.verifyYourProfile,
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
    IdentityVerificationStatus.error => l10n.verificationDescription,
    IdentityVerificationStatus.pending ||
    IdentityVerificationStatus.inProgress ||
    IdentityVerificationStatus.inReview => l10n.followVerificationInstructions,
    IdentityVerificationStatus.declined ||
    IdentityVerificationStatus.expired => l10n.tryVerificationAgain,
    IdentityVerificationStatus.verified => null,
  };
}

IconData verificationEntryIcon(
  IdentityVerificationStatus status, {
  required bool accountVerified,
}) {
  if (accountVerified || status == IdentityVerificationStatus.verified) {
    return MevoraIcons.verify;
  }
  if (status.isInFlight) {
    return MevoraIcons.pending;
  }
  if (status == IdentityVerificationStatus.declined ||
      status == IdentityVerificationStatus.expired) {
    return MevoraIcons.error;
  }
  return MevoraIcons.safety;
}
