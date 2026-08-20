import 'package:mevora/l10n/app_localizations.dart';

abstract final class SettingsStrings {
  static String validation(AppLocalizations l10n, String? key) {
    return switch (key) {
      'current_password_required' => l10n.settingsCurrentPasswordRequired,
      'new_password_required' => l10n.settingsNewPasswordRequired,
      'password_too_short' => l10n.authWeakPassword,
      'confirm_password_required' => l10n.settingsConfirmPasswordRequired,
      'passwords_do_not_match' => l10n.settingsPasswordsDoNotMatch,
      'photo_min_required' => l10n.settingsPhotoMinRequired,
      'photo_max_exceeded' => l10n.settingsPhotoMaxExceeded,
      'photo_primary_delete_blocked' => l10n.settingsPhotoPrimaryDeleteBlocked,
      'photo_primary_required' => l10n.settingsPhotoPrimaryRequired,
      'first_name_required' => l10n.settingsFirstNameRequired,
      'first_name_too_long' => l10n.settingsFirstNameTooLong,
      'bio_too_long' => l10n.settingsBioTooLong,
      'interests_too_many' => l10n.settingsInterestsTooMany,
      'must_be_adult' => l10n.onboardingMustBeAdult,
      'min_age_invalid' => l10n.settingsMinAgeInvalid,
      'max_age_invalid' => l10n.settingsMaxAgeInvalid,
      'age_range_invalid' => l10n.settingsAgeRangeInvalid,
      'distance_invalid' => l10n.settingsDistanceInvalid,
      _ => l10n.somethingWentWrong,
    };
  }

  static String genderLabel(AppLocalizations l10n, String? value) {
    return switch (value) {
      'woman' => l10n.genderWoman,
      'man' => l10n.genderMan,
      'nonBinary' => l10n.genderNonBinary,
      _ => value ?? '—',
    };
  }

  static String relationshipGoalLabel(AppLocalizations l10n, String? value) {
    return switch (value) {
      'longTerm' => l10n.relationshipGoalLongTerm,
      'casual' => l10n.relationshipGoalCasual,
      'figuringOut' => l10n.relationshipGoalFiguringOut,
      _ => value ?? '—',
    };
  }
}
