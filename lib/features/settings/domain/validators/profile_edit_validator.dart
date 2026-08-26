import 'package:mevora/core/constants/app_constants.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_config.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/settings/domain/validators/photo_policy.dart';

/// Validates editable profile fields. [UserProfile.birthDate] is immutable
/// after onboarding — age is always derived from birthDate, never edited here.
abstract final class ProfileEditValidator {
  static const int maxBioLength = 500;
  static const int maxInterests = 10;

  static String? validateFirstName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'first_name_required';
    }
    if (value.trim().length > 40) {
      return 'first_name_too_long';
    }
    return null;
  }

  static String? validateBio(String? value) {
    if (value != null && value.length > maxBioLength) {
      return 'bio_too_long';
    }
    return null;
  }

  static String? validatePhotos(List<ProfilePhoto> photos) {
    if (photos.length < PhotoPolicy.minPhotos) {
      return 'photo_min_required';
    }
    if (photos.length > PhotoPolicy.maxPhotos) {
      return 'photo_max_exceeded';
    }
    if (!photos.any((photo) => photo.isPrimary)) {
      return 'photo_primary_required';
    }
    return null;
  }

  static String? validateProfile(UserProfile profile) {
    final firstName = validateFirstName(profile.displayName);
    if (firstName != null) {
      return firstName;
    }
    final bio = validateBio(profile.bio);
    if (bio != null) {
      return bio;
    }
    final photos = validatePhotos(profile.photos);
    if (photos != null) {
      return photos;
    }
    if (profile.interests.length > maxInterests) {
      return 'interests_too_many';
    }
    if (profile.interests.length < OnboardingConfig.minInterests) {
      return 'interests_min_required';
    }
    if (profile.resolvedAge < AppConstants.minimumAge) {
      return 'must_be_adult';
    }
    return null;
  }
}
