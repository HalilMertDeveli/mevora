/// Onboarding wizard steps. Location permission is step 1 and handled separately.
enum OnboardingStep {
  basicInfo(1),
  interests(2),
  education(3),
  relationshipGoal(4),
  lifestyle(5),
  bio(6),
  photos(7),

  /// Optional Spotify stage. Sits after photos so the required profile
  /// information is already captured before anything optional is offered.
  music(8),
  complete(9);

  const OnboardingStep(this.order);

  /// Display order after location (location = 1, basicInfo = 2, …).
  final int order;

  static const int totalSteps = 10;

  int get displayStep => order + 1;

  static OnboardingStep fromStorage(Object? value) {
    if (value is int) {
      return values.firstWhere(
        (step) => step.order == value,
        orElse: () => OnboardingStep.basicInfo,
      );
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
