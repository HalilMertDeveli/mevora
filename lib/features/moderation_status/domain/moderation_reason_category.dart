/// The member-facing category for a moderation reason code.
///
/// Reason codes are staff vocabulary (functions/src/admin/actions/
/// actionTypes.ts: REASON_CODES and PHOTO_REJECT_REASONS). The app never
/// shows them raw: each maps to a calm, generic category, and anything
/// unknown or new falls back to [general] rather than guessing.
enum ModerationReasonCategory {
  harmfulBehavior,
  scamOrFraud,
  spam,
  authenticity,
  ageRequirement,
  contentRules,
  photoRequirements,
  wellbeing,
  general;

  static ModerationReasonCategory fromCode(String? code) {
    return switch (code?.trim().toUpperCase()) {
      'HARASSMENT' ||
      'HATE_SPEECH' ||
      'VIOLENCE_THREATS' => ModerationReasonCategory.harmfulBehavior,
      'SCAM_FRAUD' || 'PAYMENT_ABUSE' => ModerationReasonCategory.scamOrFraud,
      'SPAM' => ModerationReasonCategory.spam,
      'FAKE_PROFILE' ||
      'IMPERSONATION' ||
      'BAN_EVASION' ||
      'NOT_A_PERSON' => ModerationReasonCategory.authenticity,
      'UNDERAGE' || 'MINOR_IN_PHOTO' => ModerationReasonCategory.ageRequirement,
      'INAPPROPRIATE_CONTENT' ||
      'NUDITY_SEXUAL_CONTENT' ||
      'VIOLENCE_GORE' ||
      'HATE_SYMBOLS' ||
      'CONTACT_INFO' => ModerationReasonCategory.contentRules,
      'LOW_QUALITY' => ModerationReasonCategory.photoRequirements,
      'SELF_HARM_RISK' => ModerationReasonCategory.wellbeing,
      _ => ModerationReasonCategory.general,
    };
  }
}
