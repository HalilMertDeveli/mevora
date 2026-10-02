import 'package:mevora/core/constants/app_constants.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_config.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/domain/onboarding_messages.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/photo_upload_messages.dart';
import 'package:mevora/features/profile/domain/validators/person_name_validator.dart';
import 'package:mevora/features/settings/domain/validators/photo_policy.dart';

abstract final class OnboardingValidators {
  static Result<void> validateAge(DateTime? birthDate) {
    if (birthDate == null) {
      return const Err(ValidationFailure(OnboardingMessages.birthdayRequired));
    }
    final age = _ageFrom(birthDate);
    if (age < AppConstants.minimumAge) {
      return const Err(
        ValidationFailure(OnboardingMessages.underage),
      );
    }
    return const Success(null);
  }

  /// [lastName] is the member's private surname. It is validated here but
  /// never stored on the public [UserProfile].
  static Result<void> validateBasicInfo(
    UserProfile profile, {
    required String? lastName,
  }) {
    switch (PersonNameValidator.validateFirstName(profile.displayName)) {
      case PersonNameIssue.required:
        return const Err(
          ValidationFailure(OnboardingMessages.firstNameRequired),
        );
      case PersonNameIssue.tooLong:
        return const Err(ValidationFailure(OnboardingMessages.firstNameTooLong));
      case null:
        break;
    }
    switch (PersonNameValidator.validateLastName(lastName)) {
      case PersonNameIssue.required:
        return const Err(ValidationFailure(OnboardingMessages.lastNameRequired));
      case PersonNameIssue.tooLong:
        return const Err(ValidationFailure(OnboardingMessages.lastNameTooLong));
      case null:
        break;
    }
    final ageResult = validateAge(profile.birthDate);
    if (ageResult.isError) {
      return ageResult;
    }
    if (profile.gender == null || profile.gender!.isEmpty) {
      return const Err(ValidationFailure(OnboardingMessages.genderRequired));
    }
    if (profile.interestedIn == null || profile.interestedIn!.isEmpty) {
      return const Err(ValidationFailure(OnboardingMessages.interestedInRequired));
    }
    if (profile.city == null || profile.city!.trim().isEmpty) {
      return const Err(ValidationFailure(OnboardingMessages.cityRequired));
    }
    return const Success(null);
  }

  static Result<void> validateInterests(List<String> interests) {
    if (interests.length < OnboardingConfig.minInterests) {
      return Err(ValidationFailure(OnboardingMessages.interestsTooFew));
    }
    if (interests.length > OnboardingConfig.maxInterests) {
      return Err(ValidationFailure(OnboardingMessages.interestsTooMany));
    }
    return const Success(null);
  }

  static Result<void> validateEducation(String? education) {
    if (education == null || education.isEmpty) {
      return const Err(ValidationFailure(OnboardingMessages.educationRequired));
    }
    return const Success(null);
  }

  static Result<void> validateRelationshipGoal(String? goal) {
    if (goal == null || goal.isEmpty) {
      return const Err(
        ValidationFailure(OnboardingMessages.relationshipGoalRequired),
      );
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
      return const Err(ValidationFailure(OnboardingMessages.lifestyleRequired));
    }
    return const Success(null);
  }

  static Result<void> validateBio(String? bio) {
    final value = bio?.trim() ?? '';
    if (value.length < OnboardingConfig.minBioLength) {
      return Err(ValidationFailure(OnboardingMessages.bioTooShort));
    }
    if (value.length > OnboardingConfig.maxBioLength) {
      return Err(ValidationFailure(OnboardingMessages.bioTooLong));
    }
    return const Success(null);
  }

  /// [requireFaceAnchor] is what the server said about this member: when
  /// true, one photo must be a verified Face Anchor and the primary photo must
  /// be one. The other photos need not show the member at all.
  ///
  /// This spares the member a round trip; it is not the authority. The server
  /// checks the same rule against its own records when the profile completes.
  static Result<void> validatePhotos(
    List<ProfilePhoto> photos, {
    bool requireFaceAnchor = false,
  }) {
    final usable = photos.where((photo) => photo.id.isNotEmpty).length;
    if (usable < OnboardingConfig.minPhotos) {
      return const Err(ValidationFailure(PhotoUploadMessages.minRequired));
    }
    if (usable > OnboardingConfig.maxPhotos) {
      return Err(ValidationFailure(OnboardingMessages.photosTooMany));
    }
    if (requireFaceAnchor) {
      if (!PhotoPolicy.hasFaceAnchor(photos)) {
        return const Err(
          ValidationFailure(OnboardingMessages.faceAnchorRequired),
        );
      }
      final primary = photos.where((photo) => photo.isPrimary).firstOrNull;
      if (primary == null || !primary.isFaceAnchor) {
        return const Err(
          ValidationFailure(OnboardingMessages.primaryNotFaceAnchor),
        );
      }
    }
    return const Success(null);
  }

  static Result<void> validateStep(
    OnboardingStep step,
    UserProfile profile, {
    String? lastName,
    bool requireFaceAnchor = false,
  }) {
    return switch (step) {
      OnboardingStep.basicInfo => validateBasicInfo(
        profile,
        lastName: lastName,
      ),
      OnboardingStep.interests => validateInterests(profile.interests),
      OnboardingStep.education => validateEducation(profile.education),
      OnboardingStep.relationshipGoal =>
        validateRelationshipGoal(profile.relationshipGoal),
      OnboardingStep.lifestyle => validateLifestyle(profile),
      // Every question here is optional; the step only offers them.
      OnboardingStep.aboutYou => const Success(null),
      OnboardingStep.bio => validateBio(profile.bio),
      OnboardingStep.photos => validatePhotos(
        profile.photos,
        requireFaceAnchor: requireFaceAnchor,
      ),
      // Spotify is optional: there is nothing to validate, and a member who
      // skips it must still pass completion.
      OnboardingStep.music => const Success(null),
      OnboardingStep.complete => const Success(null),
    };
  }

  static Result<void> validateCompletion(
    UserProfile profile, {
    required String? lastName,
    bool requireFaceAnchor = false,
  }) {
    for (final step in OnboardingStep.values) {
      if (step == OnboardingStep.complete) {
        continue;
      }
      final result = validateStep(
        step,
        profile,
        lastName: lastName,
        requireFaceAnchor: requireFaceAnchor,
      );
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
