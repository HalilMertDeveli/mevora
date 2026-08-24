import 'package:mevora/l10n/app_localizations.dart';

abstract final class ProfileLabels {
  static String completionField(AppLocalizations l10n, String key) {
    return switch (key) {
      'displayName' => l10n.profileFieldDisplayName,
      'birthDate' => l10n.profileFieldBirthDate,
      'gender' => l10n.profileFieldGender,
      'interestedIn' => l10n.profileFieldInterestedIn,
      'city' => l10n.profileFieldCity,
      'photos' => l10n.profileFieldPhotos,
      'interests' => l10n.profileFieldInterests,
      'relationshipGoal' => l10n.profileFieldRelationshipGoal,
      'languages' => l10n.profileFieldLanguages,
      'heightCm' => l10n.profileFieldHeightCm,
      'bio' => l10n.profileFieldBio,
      'education' => l10n.profileFieldEducation,
      'occupation' => l10n.profileFieldOccupation,
      'hobbies' => l10n.profileFieldHobbies,
      'lifestyleHabits' => l10n.profileFieldLifestyleHabits,
      'lifestyleValues' => l10n.profileFieldLifestyleValues,
      _ => key,
    };
  }
}
