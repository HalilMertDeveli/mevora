import 'package:mevora/core/constants/app_constants.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_config.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/photo_upload_messages.dart';

abstract final class OnboardingValidators {
  static Result<void> validateAge(DateTime? birthDate) {
    if (birthDate == null) {
      return const Err(ValidationFailure('Birthday is required'));
    }
    final age = _ageFrom(birthDate);
    if (age < AppConstants.minimumAge) {
      return const Err(
        ValidationFailure('You must be 18 or older to use Mevora.'),
      );
    }
    return const Success(null);
  }

  static Result<void> validateBasicInfo(UserProfile profile) {
    if (profile.displayName.trim().isEmpty) {
      return const Err(ValidationFailure('First name is required'));
    }
    final ageResult = validateAge(profile.birthDate);
    if (ageResult.isError) {
      return ageResult;
    }
    if (profile.gender == null || profile.gender!.isEmpty) {
      return const Err(ValidationFailure('Gender is required'));
    }
    if (profile.interestedIn == null || profile.interestedIn!.isEmpty) {
      return const Err(ValidationFailure('Interested in is required'));
    }
    if (profile.city == null || profile.city!.trim().isEmpty) {
      return const Err(ValidationFailure('City is required'));
    }
    return const Success(null);
  }

  static Result<void> validateInterests(List<String> interests) {
    if (interests.length < OnboardingConfig.minInterests) {
      return Err(
        ValidationFailure(
          'Select at least ${OnboardingConfig.minInterests} interests',
        ),
      );
    }
    if (interests.length > OnboardingConfig.maxInterests) {
      return Err(
        ValidationFailure(
          'Select up to ${OnboardingConfig.maxInterests} interests',
        ),
      );
    }
    return const Success(null);
  }

  static Result<void> validateEducation(String? education) {
    if (education == null || education.isEmpty) {
      return const Err(ValidationFailure('Education is required'));
    }
    return const Success(null);
  }

  static Result<void> validateRelationshipGoal(String? goal) {
    if (goal == null || goal.isEmpty) {
      return const Err(ValidationFailure('Relationship goal is required'));
    }
    return const Success(null);
  }

  static Result<void> validateLifestyle(UserProfile profile) {
    final lifestyle = profile.lifestyleProfile;
    if (lifestyle.smoking == null ||
        lifestyle.smoking!.isEmpty ||
        lifestyle.drinking == null ||
        lifestyle.drinking!.isEmpty ||
        lifestyle.exercise == null ||
        lifestyle.exercise!.isEmpty ||
        lifestyle.pets == null ||
        lifestyle.pets!.isEmpty) {
      return const Err(ValidationFailure('Lifestyle details are required'));
    }
    return const Success(null);
  }

  static Result<void> validateBio(String? bio) {
    final value = bio?.trim() ?? '';
    if (value.length < OnboardingConfig.minBioLength) {
      return Err(
        ValidationFailure(
          'Bio must be at least ${OnboardingConfig.minBioLength} characters',
        ),
      );
    }
    if (value.length > OnboardingConfig.maxBioLength) {
      return Err(
        ValidationFailure(
          'Bio must be ${OnboardingConfig.maxBioLength} characters or fewer',
        ),
      );
    }
    return const Success(null);
  }

  static Result<void> validatePhotos(List<ProfilePhoto> photos) {
    final usable = photos.where((photo) => photo.id.isNotEmpty).length;
    if (usable < OnboardingConfig.minPhotos) {
      return const Err(ValidationFailure(PhotoUploadMessages.minRequired));
    }
    if (usable > OnboardingConfig.maxPhotos) {
      return Err(
        ValidationFailure(
          'You can add up to ${OnboardingConfig.maxPhotos} photos',
        ),
      );
    }
    return const Success(null);
  }

  static Result<void> validateStep(OnboardingStep step, UserProfile profile) {
    return switch (step) {
      OnboardingStep.basicInfo => validateBasicInfo(profile),
      OnboardingStep.interests => validateInterests(profile.interests),
      OnboardingStep.education => validateEducation(profile.education),
      OnboardingStep.relationshipGoal =>
        validateRelationshipGoal(profile.relationshipGoal),
      OnboardingStep.lifestyle => validateLifestyle(profile),
      OnboardingStep.bio => validateBio(profile.bio),
      OnboardingStep.photos => validatePhotos(profile.photos),
      OnboardingStep.complete => const Success(null),
    };
  }

  static Result<void> validateCompletion(UserProfile profile) {
    for (final step in OnboardingStep.values) {
      if (step == OnboardingStep.complete) {
        continue;
      }
      final result = validateStep(step, profile);
      if (result.isError) {
        return result;
      }
    }
    return const Success(null);
  }

  static int _ageFrom(DateTime birthDate) {
    final today = DateTime.now();
    var years = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      years -= 1;
    }
    return years;
  }
}
