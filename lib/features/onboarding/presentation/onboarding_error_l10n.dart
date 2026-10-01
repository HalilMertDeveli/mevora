import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_config.dart';
import 'package:mevora/features/onboarding/domain/onboarding_messages.dart';
import 'package:mevora/features/profile/domain/photo_upload_messages.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Turns an onboarding failure into the member's language. Anything it does
/// not recognise falls through to the app-wide [L10nErrors] mapping.
abstract final class OnboardingErrorL10n {
  static String message(AppLocalizations l10n, String raw) {
    if (raw == OnboardingMessages.birthdayRequired) {
      return l10n.onboardingErrorBirthday;
    }
    if (raw == OnboardingMessages.underage) return l10n.onboardingMustBeAdult;
    if (raw == OnboardingMessages.firstNameRequired) {
      return l10n.onboardingErrorFirstName;
    }
    if (raw == OnboardingMessages.firstNameTooLong) {
      return l10n.settingsFirstNameTooLong;
    }
    if (raw == OnboardingMessages.lastNameRequired) {
      return l10n.onboardingErrorLastName;
    }
    if (raw == OnboardingMessages.lastNameTooLong) {
      return l10n.settingsLastNameTooLong;
    }
    if (raw == OnboardingMessages.genderRequired) {
      return l10n.onboardingErrorGender;
    }
    if (raw == OnboardingMessages.interestedInRequired) {
      return l10n.onboardingErrorInterestedIn;
    }
    if (raw == OnboardingMessages.cityRequired) return l10n.onboardingErrorCity;
    if (raw == OnboardingMessages.educationRequired) {
      return l10n.onboardingErrorEducation;
    }
    if (raw == OnboardingMessages.relationshipGoalRequired) {
      return l10n.onboardingErrorRelationshipGoal;
    }
    if (raw == OnboardingMessages.lifestyleRequired ||
        raw == OnboardingMessages.serverLifestyleRequired) {
      return l10n.onboardingErrorLifestyle;
    }
    if (raw == OnboardingMessages.interestsTooFew ||
        raw == OnboardingMessages.serverInterestsRequired) {
      return l10n.interestsMinRequired;
    }
    if (raw == OnboardingMessages.interestsTooMany) {
      return l10n.onboardingErrorInterestsMax(OnboardingConfig.maxInterests);
    }
    if (raw == OnboardingMessages.bioTooShort) {
      return l10n.onboardingErrorBioShort(OnboardingConfig.minBioLength);
    }
    if (raw == OnboardingMessages.bioTooLong) {
      return l10n.onboardingErrorBioLong(OnboardingConfig.maxBioLength);
    }
    if (raw == OnboardingMessages.photosTooMany) {
      return l10n.onboardingErrorPhotosMax(OnboardingConfig.maxPhotos);
    }
    if (raw == PhotoUploadMessages.minRequired ||
        raw == OnboardingMessages.serverPhotosRequired) {
      return l10n.photoMinRequired;
    }
    if (raw == PhotoUploadMessages.noneSelected) return l10n.photoNoneSelected;
    if (raw == PhotoUploadMessages.needSignIn) return l10n.photoNeedSignIn;
    if (raw == PhotoUploadMessages.invalidFile) return l10n.photoInvalidFile;
    if (raw == PhotoUploadMessages.failed || raw == PhotoUploadMessages.timeout) {
      return l10n.photoUploadFailed;
    }
    if (raw == PhotoUploadMessages.keepMin) {
      return l10n.settingsPhotoMinRequired;
    }
    if (raw == OnboardingMessages.serverPhotosInReview) {
      return l10n.onboardingErrorPhotosInReview;
    }
    if (raw == OnboardingMessages.serverProfileMissing) {
      return l10n.onboardingErrorProfileIncomplete;
    }
    if (raw == OnboardingMessages.serverSignInAgain) {
      return l10n.onboardingErrorSignInAgain;
    }
    if (raw == OnboardingMessages.serverNotAllowed) {
      return l10n.onboardingErrorNotAllowed;
    }
    if (raw.startsWith(OnboardingMessages.serverGenericPrefix)) {
      return l10n.onboardingErrorGeneric;
    }
    return L10nErrors.message(l10n, raw);
  }
}
