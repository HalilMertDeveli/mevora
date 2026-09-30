import 'package:flutter/material.dart';
import 'package:mevora/core/identity/account_status.dart';
import 'package:mevora/features/moderation_status/domain/models/moderation_status.dart';
import 'package:mevora/features/moderation_status/domain/moderation_reason_category.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Member-facing wording for moderation data. Raw codes never reach the UI.
abstract final class ModerationLabels {
  static String accountStatus(AppLocalizations l10n, AccountStatus status) {
    return switch (status) {
      AccountStatus.active => l10n.moderationStatusActive,
      AccountStatus.suspended => l10n.moderationStatusSuspended,
      AccountStatus.banned => l10n.moderationStatusBanned,
      AccountStatus.disabled ||
      AccountStatus.deleted => l10n.moderationStatusInactive,
    };
  }

  static String decisionType(
    AppLocalizations l10n,
    ModerationDecisionType type,
  ) {
    return switch (type) {
      ModerationDecisionType.warning => l10n.moderationTypeWarning,
      ModerationDecisionType.temporarySuspension =>
        l10n.moderationTypeTemporarySuspension,
      ModerationDecisionType.permanentBan => l10n.moderationTypePermanentBan,
      ModerationDecisionType.photoRejected => l10n.moderationTypePhotoRejected,
      ModerationDecisionType.photoRemoved => l10n.moderationTypePhotoRemoved,
      ModerationDecisionType.requireReverification =>
        l10n.moderationTypeRequireReverification,
      ModerationDecisionType.unknown => l10n.moderationTypeOther,
    };
  }

  static String reason(AppLocalizations l10n, String? reasonCode) {
    return switch (ModerationReasonCategory.fromCode(reasonCode)) {
      ModerationReasonCategory.harmfulBehavior =>
        l10n.moderationReasonHarmfulBehavior,
      ModerationReasonCategory.scamOrFraud => l10n.moderationReasonScamOrFraud,
      ModerationReasonCategory.spam => l10n.moderationReasonSpam,
      ModerationReasonCategory.authenticity =>
        l10n.moderationReasonAuthenticity,
      ModerationReasonCategory.ageRequirement =>
        l10n.moderationReasonAgeRequirement,
      ModerationReasonCategory.contentRules =>
        l10n.moderationReasonContentRules,
      ModerationReasonCategory.photoRequirements =>
        l10n.moderationReasonPhotoRequirements,
      ModerationReasonCategory.wellbeing => l10n.moderationReasonWellbeing,
      ModerationReasonCategory.general => l10n.moderationReasonGeneral,
    };
  }

  static String appealOutcome(
    AppLocalizations l10n,
    AppealSubmitOutcome outcome,
  ) {
    return switch (outcome) {
      AppealSubmitOutcome.created => l10n.moderationAppealSent,
      AppealSubmitOutcome.alreadySubmitted => l10n.moderationAppealAlreadySent,
      AppealSubmitOutcome.windowClosed => l10n.moderationAppealWindowClosed,
      AppealSubmitOutcome.notAllowed => l10n.moderationAppealNotAllowed,
      AppealSubmitOutcome.invalidReason => l10n.moderationAppealInvalid,
      AppealSubmitOutcome.failed => l10n.moderationAppealFailed,
    };
  }

  /// Local date and time in the member's locale.
  static String dateTime(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final material = MaterialLocalizations.of(context);
    return '${material.formatMediumDate(local)} '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }
}
