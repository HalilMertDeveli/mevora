import 'package:mevora/features/onboarding/domain/entities/onboarding_config.dart';

/// Stable identifiers for onboarding validation and completion failures.
///
/// Domain code returns these; the presentation layer turns them into the
/// member's language through `OnboardingErrorL10n`. They stay readable English
/// so logs and tests remain meaningful, but they are never shown as-is.
abstract final class OnboardingMessages {
  static const birthdayRequired = 'Birthday is required';
  static const underage = 'You must be 18 or older to use Mevora.';
  static const firstNameRequired = 'First name is required';
  static const firstNameTooLong = 'First name is too long';
  static const lastNameRequired = 'Last name is required';
  static const lastNameTooLong = 'Last name is too long';
  static const genderRequired = 'Gender is required';
  static const interestedInRequired = 'Interested in is required';
  static const cityRequired = 'City is required';
  static const educationRequired = 'Education is required';
  static const relationshipGoalRequired = 'Relationship goal is required';
  static const lifestyleRequired = 'Lifestyle details are required';

  static final interestsTooFew =
      'Select at least ${OnboardingConfig.minInterests} interests';
  static final interestsTooMany =
      'Select up to ${OnboardingConfig.maxInterests} interests';
  static final bioTooShort =
      'Bio must be at least ${OnboardingConfig.minBioLength} characters';
  static final bioTooLong =
      'Bio must be ${OnboardingConfig.maxBioLength} characters or fewer';
  static final photosTooMany =
      'You can add up to ${OnboardingConfig.maxPhotos} photos';

  // Completion failures reported by the completeOnboarding callable.
  static const serverPhotosRequired =
      'Add at least 3 photos to finish onboarding.';
  static const serverPhotosInReview =
      'Photos are still under review. Please try again shortly.';
  static const serverInterestsRequired =
      'Pick at least 3 interests to continue.';
  static const serverLifestyleRequired =
      'Complete lifestyle answers to finish onboarding.';
  static const serverProfileMissing =
      'Profile is incomplete. Please go back and fill required fields.';
  static const serverSignInAgain = 'Please sign in again to finish onboarding.';
  static const serverNotAllowed = 'This account cannot complete onboarding.';

  /// Prefix of the generic completion failure (debug builds append details).
  static const serverGenericPrefix = 'Could not complete onboarding';
}
