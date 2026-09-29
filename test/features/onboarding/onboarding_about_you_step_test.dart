import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/domain/validators/onboarding_validators.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

void main() {
  test('"Get to know you" follows lifestyle and leads to bio', () {
    expect(OnboardingStep.lifestyle.next, OnboardingStep.aboutYou);
    expect(OnboardingStep.aboutYou.next, OnboardingStep.bio);
    expect(OnboardingStep.bio.previous, OnboardingStep.aboutYou);
    expect(OnboardingStep.complete.displayStep, OnboardingStep.totalSteps);
  });

  test('it is saved and restored by name', () {
    expect(
      OnboardingStep.fromStorage(OnboardingStep.aboutYou.name),
      OnboardingStep.aboutYou,
    );
  });

  test('old numeric progress still lands on the same screen', () {
    // Numbers were written before the step existed; inserting it must not
    // move a member who stopped at bio onto the new step.
    expect(OnboardingStep.fromStorage(5), OnboardingStep.lifestyle);
    expect(OnboardingStep.fromStorage(6), OnboardingStep.bio);
    expect(OnboardingStep.fromStorage(7), OnboardingStep.photos);
    expect(OnboardingStep.fromStorage(9), OnboardingStep.complete);
  });

  test('every question in it is optional', () {
    const profile = UserProfile(uid: 'u', displayName: 'Ada');
    expect(
      OnboardingValidators.validateStep(
        OnboardingStep.aboutYou,
        profile,
      ).isSuccess,
      isTrue,
    );
  });
}
