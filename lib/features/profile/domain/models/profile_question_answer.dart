class ProfileQuestionAnswer {
  const ProfileQuestionAnswer({
    required this.questionId,
    required this.answerId,
    required this.isVisible,
    this.answerLocked = false,
    this.createdAt,
    this.updatedAt,
  });

  final String questionId;
  /// Empty when [answerLocked] — free clients never receive peer answer ids.
  final String answerId;
  final bool isVisible;
  /// True when the question prompt is visible but the answer requires Premium.
  final bool answerLocked;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

/// Server payload for peer profile question answers (via Cloud Function).
class PartnerQuestionAnswersSnapshot {
  const PartnerQuestionAnswersSnapshot({
    required this.locked,
    required this.matchRequired,
    required this.premiumRequired,
    required this.isPremium,
    required this.items,
  });

  final bool locked;
  final bool matchRequired;
  final bool premiumRequired;
  final bool isPremium;
  final List<ProfileQuestionAnswer> items;

  static const empty = PartnerQuestionAnswersSnapshot(
    locked: true,
    matchRequired: true,
    premiumRequired: false,
    isPremium: false,
    items: [],
  );
}
