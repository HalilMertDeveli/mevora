enum CompatibilityCategory {
  overall,
  relationship,
  interests,
  languages,
  hobbies,
  lifestyle,
  lifeValues,
  questions,
  music,
  communication,
  proximity,
  activity,
}

enum CompatibilityReasonPriority { high, medium, low }

/// UI-agnostic explanation for why two people match.
class CompatibilityReason {
  const CompatibilityReason({
    required this.messageKey,
    this.messageArgs = const [],
    required this.category,
    this.priority = CompatibilityReasonPriority.medium,
    this.iconName = 'favorite',
  });

  /// Localization key (resolved in presentation).
  final String messageKey;
  final List<String> messageArgs;
  final CompatibilityCategory category;
  final CompatibilityReasonPriority priority;
  final String iconName;
}
