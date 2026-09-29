import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/features/onboarding/domain/validators/onboarding_validators.dart';
import 'package:mevora/features/onboarding/presentation/onboarding_error_l10n.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/photo_upload_messages.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Onboarding failures are English identifiers in the domain; a Turkish member
/// must never read them as-is.
void main() {
  final tr = lookupAppLocalizations(const Locale('tr'));
  final en = lookupAppLocalizations(const Locale('en'));

  String shown(AppLocalizations l10n, UserProfile profile) {
    final result = OnboardingValidators.validateBasicInfo(profile);
    final failure = result.failureOrNull! as ValidationFailure;
    return OnboardingErrorL10n.message(l10n, failure.message);
  }

  test('a missing city reads in the member language', () {
    final profile = UserProfile(
      uid: 'u',
      displayName: 'Deniz',
      birthDate: DateTime(2000, 1, 1),
      gender: 'woman',
      interestedIn: 'men',
    );
    expect(shown(tr, profile), 'Şehrini seç.');
    expect(shown(en, profile), 'Choose your city.');
  });

  test('limits come from the onboarding config, not hard-coded copy', () {
    final result = OnboardingValidators.validateBio('kısa');
    final failure = result.failureOrNull! as ValidationFailure;
    expect(
      OnboardingErrorL10n.message(tr, failure.message),
      'Kendinden en az 10 karakterle bahset.',
    );
  });

  test('the generic completion failure is localized, debug details or not', () {
    expect(
      OnboardingErrorL10n.message(
        tr,
        'Could not complete onboarding (internal: boom).',
      ),
      'Profilin tamamlanamadı. Lütfen tekrar dene.',
    );
  });

  test('photo messages read in the member language either way', () {
    expect(
      OnboardingErrorL10n.message(en, PhotoUploadMessages.minRequired),
      'You must add at least 3 photos.',
    );
    expect(
      OnboardingErrorL10n.message(tr, PhotoUploadMessages.noneSelected),
      'Fotoğraf seçilmedi.',
    );
  });
}
