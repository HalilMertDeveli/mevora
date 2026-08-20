import 'package:mevora/core/constants/app_constants.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/onboarding/domain/repositories/onboarding_repository.dart';
import 'package:mevora/features/onboarding/domain/validators/onboarding_validators.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

class CompleteOnboarding {
  const CompleteOnboarding(this._onboarding);

  final OnboardingRepository _onboarding;

  Future<Result<UserProfile>> call(UserProfile profile) {
    return _onboarding.complete(profile);
  }
}

class ValidateOnboardingAge {
  const ValidateOnboardingAge();

  Result<void> call(DateTime? birthDate) => OnboardingValidators.validateAge(birthDate);
}

class ValidateOnboardingInterests {
  const ValidateOnboardingInterests();

  Result<void> call(List<String> interests) =>
      OnboardingValidators.validateInterests(interests);
}

class ValidateOnboardingPhotos {
  const ValidateOnboardingPhotos();

  Result<void> call(List<ProfilePhoto> photos) =>
      OnboardingValidators.validatePhotos(photos);
}

class ValidateProfileCompletion {
  const ValidateProfileCompletion();

  Result<void> call(UserProfile profile) =>
      OnboardingValidators.validateCompletion(profile);
}
