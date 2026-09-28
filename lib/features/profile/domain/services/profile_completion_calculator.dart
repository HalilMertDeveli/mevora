import 'package:mevora/features/onboarding/domain/entities/onboarding_config.dart';
import 'package:mevora/features/profile/domain/catalog/height_catalog.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

/// Profile completeness for edit-profile nudges. Never blocks discover access.
class ProfileCompletionResult {
  const ProfileCompletionResult({
    required this.percent,
    required this.missingFieldKeys,
  });

  final int percent;
  final List<String> missingFieldKeys;

  bool get isComplete => percent >= 100;
}

abstract final class ProfileCompletionCalculator {
  static const _weights = <String, int>{
    'displayName': 5,
    'birthDate': 5,
    'gender': 5,
    'interestedIn': 5,
    'city': 5,
    'photos': 10,
    'interests': 10,
    'relationshipGoal': 5,
    'languages': 8,
    'heightCm': 5,
    'bio': 5,
    'education': 5,
    'occupation': 5,
    'hobbies': 7,
    'lifestyleHabits': 8,
    'lifestyleValues': 7,
  };

  static ProfileCompletionResult calculate(UserProfile profile) {
    var earned = 0;
    final missing = <String>[];

    void check(String key, bool filled) {
      final weight = _weights[key] ?? 0;
      if (filled) {
        earned += weight;
      } else {
        missing.add(key);
      }
    }

    check('displayName', profile.displayName.trim().isNotEmpty);
    check('birthDate', profile.birthDate != null || (profile.age ?? 0) > 0);
    check('gender', profile.gender != null && profile.gender!.isNotEmpty);
    check(
      'interestedIn',
      profile.interestedIn != null && profile.interestedIn!.isNotEmpty,
    );
    check('city', profile.city != null && profile.city!.trim().isNotEmpty);
    check(
      'photos',
      profile.photos.where((photo) => photo.isPublic).length >=
          OnboardingConfig.minPhotos,
    );
    check(
      'interests',
      profile.interests.length >= OnboardingConfig.minInterests,
    );
    check(
      'relationshipGoal',
      profile.relationshipGoal != null && profile.relationshipGoal!.isNotEmpty,
    );
    check('languages', profile.languages.isNotEmpty);
    check('heightCm', HeightCatalog.isValid(profile.heightCm));
    check('bio', (profile.bio ?? '').trim().length >= OnboardingConfig.minBioLength);
    check('education', profile.education != null && profile.education!.isNotEmpty);
    check('occupation', profile.occupation != null && profile.occupation!.trim().isNotEmpty);
    check('hobbies', profile.hobbies.isNotEmpty);

    final lifestyle = profile.lifestyleProfile;
    final habitsFilled = lifestyle.smoking != null &&
        lifestyle.drinking != null &&
        lifestyle.exercise != null &&
        lifestyle.pets != null;
    check('lifestyleHabits', habitsFilled);

    final valuesFilled = lifestyle.childrenPreference != null &&
        lifestyle.partnerSmokingPref != null &&
        lifestyle.partnerDrinkingPref != null;
    check('lifestyleValues', valuesFilled);

    final total = _weights.values.fold<int>(0, (sum, weight) => sum + weight);
    final percent = total == 0 ? 0 : ((earned / total) * 100).round().clamp(0, 100);
    return ProfileCompletionResult(percent: percent, missingFieldKeys: missing);
  }
}
