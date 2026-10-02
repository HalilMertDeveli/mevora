import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/onboarding/presentation/onboarding_labels.dart';
import 'package:mevora/features/support/domain/content/support_content.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Wording found on a real Turkish phone in the final acceptance run: English
/// left in the Turkish UI, a first-run screen that said "let's continue", a
/// dialog whose body was its own button label, and the same help question
/// asked twice.
void main() {
  final tr = lookupAppLocalizations(const Locale('tr'));
  final en = lookupAppLocalizations(const Locale('en'));

  group('Turkish UI carries no English leftovers', () {
    test('the gender option is in Turkish', () {
      expect(tr.onboardingGenderNonBinary, 'İkili olmayan');
      expect(tr.genderNonBinary, 'İkili olmayan');
    });

    test('the birthday note does not say "onboarding"', () {
      expect(tr.settingsBirthDateLocked.toLowerCase(), isNot(contains('onboarding')));
      expect(tr.settingsBirthDateLocked, contains('kayıt'));
    });
  });

  group('a language someone speaks', () {
    test('is named in the language the app is showing', () {
      expect(OnboardingLabels.language(tr, 'english'), 'İngilizce 🇬🇧');
      expect(OnboardingLabels.language(tr, 'turkish'), 'Türkçe 🇹🇷');
      expect(OnboardingLabels.language(en, 'english'), 'English 🇬🇧');
      expect(OnboardingLabels.language(en, 'turkish'), 'Turkish 🇹🇷');
      // The neighbours were already translated; these two were the odd ones.
      expect(OnboardingLabels.language(tr, 'german'), 'Almanca 🇩🇪');
    });

    test("the app's own language switch still writes each language in itself", () {
      for (final l10n in [tr, en]) {
        expect(l10n.languageTurkish, 'Türkçe 🇹🇷');
        expect(l10n.languageEnglish, 'English 🇬🇧');
      }
    });
  });

  test('the Humor Lab line reads right before the first rating', () {
    // It is shown at 0 / 15 as well as mid-way, so it cannot say "continue".
    expect(tr.humorLabSubtitle, isNot(contains('devam')));
    expect(en.humorLabSubtitle.toLowerCase(), isNot(startsWith('keep')));
  });

  test('the photo confirmation says something its button does not', () {
    for (final l10n in [tr, en]) {
      expect(l10n.previewPhotoBody, isNot(l10n.send));
      expect(l10n.previewPhotoBody.length, greaterThan(l10n.send.length));
    }
  });

  group('help questions', () {
    for (final (name, l10n, deletePath) in [
      ('Turkish', tr, 'Hesabı Sil'),
      ('English', en, 'Delete Account'),
    ]) {
      test('ask how to delete an account once ($name)', () {
        final entries = SupportContent.faqEntries(l10n);

        final questions = entries.map((entry) => entry.question).toList();
        expect(questions.toSet(), hasLength(questions.length));
        final aboutDeleting = entries
            .where((entry) => entry.answer.contains(deletePath))
            .toList();
        expect(aboutDeleting, hasLength(1));
        // What the removed "close my account" entry added is kept.
        expect(
          aboutDeleting.single.answer,
          contains(l10n == tr ? 'çıkış yapmak' : 'Logging out'),
        );
      });
    }
  });
}
