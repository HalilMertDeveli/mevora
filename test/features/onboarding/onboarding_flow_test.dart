import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/routing/auth_redirector.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/domain/validators/onboarding_validators.dart';
import 'package:mevora/features/onboarding/domain/usecases/onboarding_usecases.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

import '../../helpers/fake_onboarding_services.dart';

void main() {
  test('onboarding state resumes from saved step', () {
    const profile = UserProfile(
      uid: 'u1',
      displayName: 'Ada',
      onboardingStep: OnboardingStep.bio,
    );
    expect(profile.onboardingStep, OnboardingStep.bio);
    expect(OnboardingStep.fromStorage('bio'), OnboardingStep.bio);
    expect(OnboardingStep.fromStorage(6), OnboardingStep.bio);
  });

  test('complete onboarding use case validates profile', () async {
    final repo = FakeOnboardingRepository();
    final useCase = CompleteOnboarding(repo);
    final result = await useCase.call(
      const UserProfile(uid: 'u1', displayName: 'Ada'),
    );
    expect(result.isError, isTrue);
  });

  test('auth redirect sends incomplete users to onboarding', () {
    const user = AuthUser(id: 'u1');
    expect(
      AuthRedirector.redirect(
        status: const NeedsOnboarding(user),
        location: AppRoutes.discovery,
        needsLocationOnboarding: false,
      ),
      AppRoutes.onboarding,
    );
  });

  test('validate profile completion use case accepts complete draft', () {
    const profile = UserProfile(
      uid: 'u1',
      displayName: 'Ada',
      birthDate: null,
    );
    final complete = profile.copyWith(
      birthDate: DateTime(1995, 5, 5),
      gender: 'woman',
      interestedIn: 'men',
      city: 'Berlin',
      interests: ['music', 'travel', 'food'],
      education: 'bachelors',
      relationshipGoal: 'long_term',
      lifestyleProfile: ProfileLifestyle(
        smoking: 'never',
        drinking: 'never',
        exercise: 'regularly',
        pets: 'dog',
      ),
      bio: 'Looking for good conversation and coffee.',
      photos: [
        ProfilePhoto(id: '1', storagePath: 'a'),
        ProfilePhoto(id: '2', storagePath: 'b'),
        ProfilePhoto(id: '3', storagePath: 'c'),
      ],
    );
    expect(const ValidateProfileCompletion().call(complete).isSuccess, isTrue);
  });
}
