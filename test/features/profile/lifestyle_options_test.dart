import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/discovery/domain/compatibility/compatibility_engine.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_enums.dart';
import 'package:mevora/features/onboarding/presentation/onboarding_labels.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_extended_lifestyle_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_lifestyle_picker.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('lifestyle values', () {
    test(
      'diet survives copyWith, the stored map and the compatibility tags',
      () {
        final lifestyle = const ProfileLifestyle(
          smoking: OnboardingLifestyleOption.quitting,
        ).copyWith(diet: DietPreference.vegetarian);

        expect(lifestyle.diet, DietPreference.vegetarian);
        // An unrelated copy must not drop it.
        expect(lifestyle.copyWith(pets: 'cat').diet, DietPreference.vegetarian);
        final restored = ProfileLifestyle.fromMap(lifestyle.toMap());
        expect(restored.diet, DietPreference.vegetarian);
        expect(restored.smoking, OnboardingLifestyleOption.quitting);
        expect(lifestyle.toTags(), contains('diet:vegetarian'));
        expect(const ProfileLifestyle(diet: 'vegan').isEmpty, isFalse);
      },
    );

    test('new habit answers still score against a partner preference', () {
      int? level(String v) => CompatibilityScoring.habitLevel(v);
      expect(level(OnboardingLifestyleOption.sober), 0);
      expect(level(OnboardingLifestyleOption.quitting), 1);
      expect(level(OnboardingLifestyleOption.alcoholSpecialOccasion), 1);
      expect(level(OnboardingLifestyleOption.vapeOnly), 2);
      expect(level(OnboardingLifestyleOption.preferNotToSay), isNull);
    });

    for (final locale in AppLocalizations.supportedLocales) {
      test('every option has a real label (${locale.languageCode})', () {
        final l10n = lookupAppLocalizations(locale);
        for (final (values, label) in [
          (OnboardingLifestyleOption.smokingValues, OnboardingLabels.lifestyle),
          (
            OnboardingLifestyleOption.exerciseValues,
            OnboardingLabels.lifestyle,
          ),
          (OnboardingLifestyleOption.petValues, OnboardingLabels.lifestyle),
          (OnboardingLifestyleOption.drinkingValues, OnboardingLabels.alcohol),
          (DietPreference.values, OnboardingLabels.diet),
        ]) {
          for (final value in values) {
            final text = label(l10n, value);
            expect(text, isNot(value), reason: 'raw value shown for $value');
            expect(text.trim(), isNotEmpty);
          }
        }
      });
    }
  });

  testWidgets('the lifestyle picker offers the longer lists and diet', (
    tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    ProfileLifestyle? changed;
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      wrapWithApp(
        SingleChildScrollView(
          child: ProfileLifestylePicker(
            profile: const ProfileLifestyle(),
            onChanged: (next) => changed = next,
          ),
        ),
      ),
    );

    expect(find.text(l10n.onboardingSmokingQuitting), findsOneWidget);
    expect(find.text(l10n.onboardingExerciseAthlete), findsOneWidget);
    expect(find.text(l10n.onboardingPetsAllergic), findsOneWidget);
    expect(find.text(l10n.onboardingAlcoholSober), findsOneWidget);
    await tester.tap(find.text(l10n.dietVegetarian));
    expect(changed?.diet, DietPreference.vegetarian);
  });

  testWidgets('"Get to know you" groups share one left edge', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      wrapWithApp(
        SingleChildScrollView(
          child: ProfileExtendedLifestylePicker(
            profile: const ProfileLifestyle(),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    // The screenshot bug: "Do you want children?" sat further in than the
    // partner-preference groups around it.
    final lefts = {
      for (final title in [
        l10n.profilePartnerSmokingPref,
        l10n.profileChildrenPreference,
      ])
        tester.getTopLeft(find.text(title)).dx,
    };
    expect(lefts, hasLength(1));
    expect(lefts.single, 0);
  });
}
