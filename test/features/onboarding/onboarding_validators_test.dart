import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_config.dart';
import 'package:mevora/features/onboarding/domain/validators/onboarding_validators.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

void main() {
  final adultBirthDate = DateTime(1998, 1, 1);
  final minorBirthDate = DateTime(2010, 1, 1);

  test('age validation requires 18+', () {
    expect(OnboardingValidators.validateAge(minorBirthDate).isError, isTrue);
    expect(OnboardingValidators.validateAge(adultBirthDate).isSuccess, isTrue);
  });

  test('exact 18th birthday and 17th birthday edge cases', () {
    final today = DateTime.now();
    final seventeenthBirthday = DateTime(today.year - 17, today.month, today.day);
    final eighteenthBirthday = DateTime(today.year - 18, today.month, today.day);
    final nineteenthBirthday = DateTime(today.year - 19, today.month, today.day);

    expect(OnboardingValidators.validateAge(seventeenthBirthday).isError, isTrue);
    expect(OnboardingValidators.validateAge(eighteenthBirthday).isSuccess, isTrue);
    expect(OnboardingValidators.validateAge(nineteenthBirthday).isSuccess, isTrue);
  });

  test('interests enforce min and max', () {
    expect(
      OnboardingValidators.validateInterests(['a', 'b']).isError,
      isTrue,
    );
    expect(
      OnboardingValidators.validateInterests(
        List.generate(OnboardingConfig.minInterests, (i) => 'i$i'),
      ).isSuccess,
      isTrue,
    );
    expect(
      OnboardingValidators.validateInterests(
        List.generate(OnboardingConfig.maxInterests + 1, (i) => 'i$i'),
      ).isError,
      isTrue,
    );
  });

  test('photos enforce minimum count', () {
    expect(
      OnboardingValidators.validatePhotos(const []).isError,
      isTrue,
    );
    expect(
      OnboardingValidators.validatePhotos([
        for (var i = 0; i < OnboardingConfig.minPhotos; i++)
          ProfilePhoto(id: '$i', storagePath: 'path/$i'),
      ]).isSuccess,
      isTrue,
    );
  });

  test('profile completion validates all onboarding fields', () {
    final complete = UserProfile(
      uid: 'u1',
      displayName: 'Ada',
      birthDate: adultBirthDate,
      gender: 'woman',
      interestedIn: 'men',
      city: 'Istanbul',
      interests: ['music', 'travel', 'food'],
      education: 'bachelors',
      relationshipGoal: 'long_term',
      lifestyleProfile: const ProfileLifestyle(
        smoking: 'never',
        drinking: 'sometimes',
        exercise: 'regularly',
        pets: 'cat',
      ),
      bio: 'Coffee, books, and long walks.',
      photos: [
        for (var i = 0; i < OnboardingConfig.minPhotos; i++)
          ProfilePhoto(id: '$i', storagePath: 'path/$i'),
      ],
    );

    expect(OnboardingValidators.validateCompletion(complete).isSuccess, isTrue);
    expect(
      OnboardingValidators.validateCompletion(
        complete.copyWith(bio: 'short'),
      ).isError,
      isTrue,
    );
  });
}
