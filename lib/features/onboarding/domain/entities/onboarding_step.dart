/// Onboarding wizard steps. Location permission is step 1 and handled separately.
enum OnboardingStep {
  basicInfo(1),
  interests(2),
  education(3),
  relationshipGoal(4),
  lifestyle(5),

  /// Optional "Get to know you": partner preferences, children, rhythm,
  /// weekends, living together. Steps are stored by name, so inserting it
  /// does not move a member who is part-way through onboarding.
  aboutYou(6),
  bio(7),
  photos(8),

  /// Optional Spotify stage. Sits after photos so the required profile
  /// information is already captured before anything optional is offered.
  music(9),
  complete(10);

  const OnboardingStep(this.order);

  /// Display order after location (location = 1, basicInfo = 2, …).
  final int order;

  static const int totalSteps = 11;

  int get displayStep => order + 1;

  /// Integer storage predates named steps. Its numbers are frozen to the
  /// order of that time, so a step added later (aboutYou) never shifts a
  /// member's saved progress onto a different screen.
  static const Map<int, OnboardingStep> _legacyOrder = {
    1: OnboardingStep.basicInfo,
    2: OnboardingStep.interests,
    3: OnboardingStep.education,
    4: OnboardingStep.relationshipGoal,
    5: OnboardingStep.lifestyle,
    6: OnboardingStep.bio,
    7: OnboardingStep.photos,
    8: OnboardingStep.music,
    9: OnboardingStep.complete,
  };

  static OnboardingStep fromStorage(Object? value) {
    if (value is int) {
      return _legacyOrder[value] ?? OnboardingStep.basicInfo;
    }
    if (value is String) {
      return values.firstWhere(
        (step) => step.name == value,
        orElse: () => OnboardingStep.basicInfo,
      );
    }
    return OnboardingStep.basicInfo;
  }

  OnboardingStep? get next {
    final index = order;
    if (index >= OnboardingStep.complete.order) {
      return null;
    }
    return values.firstWhere((step) => step.order == index + 1);
  }

  OnboardingStep? get previous {
    final index = order;
    if (index <= OnboardingStep.basicInfo.order) {
      return null;
    }
    return values.firstWhere((step) => step.order == index - 1);
  }
}
