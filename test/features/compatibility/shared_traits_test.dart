import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_reason.dart';
import 'package:mevora/features/compatibility/domain/services/shared_traits.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_ui.dart';
import 'package:mevora/features/compatibility/presentation/widgets/shared_traits_section.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_enums.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/l10n/app_localizations.dart';

final _tr = lookupAppLocalizations(const Locale('tr'));

const _viewer = UserProfile(
  uid: 'me',
  displayName: 'Halil',
  age: 28,
  relationshipGoal: OnboardingRelationshipGoal.longTerm,
  interests: ['travel', 'coffee', 'chess'],
  languages: ['turkish', 'english'],
  city: 'İstanbul',
  lifestyleProfile: ProfileLifestyle(
    smoking: OnboardingLifestyleOption.never,
    drinking: OnboardingLifestyleOption.alcoholSpecialOccasion,
    pets: OnboardingLifestyleOption.preferNotToSay,
    diet: DietPreference.vegetarian,
    childrenPreference: ChildrenPreference.yes,
    partnerSmokingPref: PartnerPreference.never,
    weekendPreferences: [WeekendPreference.nature, WeekendPreference.movies],
  ),
);

DiscoveryCandidate _candidate({
  int age = 26,
  ProfileLifestyle lifestyle = const ProfileLifestyle(
    smoking: OnboardingLifestyleOption.never,
    drinking: OnboardingLifestyleOption.alcoholSpecialOccasion,
    pets: OnboardingLifestyleOption.preferNotToSay,
    diet: DietPreference.vegetarian,
    childrenPreference: ChildrenPreference.yes,
    partnerDrinkingPref: PartnerPreference.prefer,
    weekendPreferences: [WeekendPreference.movies, WeekendPreference.party],
  ),
}) => DiscoveryCandidate(
  uid: 'ada',
  displayName: 'Ada',
  age: age,
  photos: const [],
  relationshipGoal: OnboardingRelationshipGoal.longTerm,
  interests: const ['coffee', 'travel', 'yoga'],
  languages: const ['english'],
  city: 'istanbul',
  lifestyleProfile: lifestyle,
  relationshipAlignedCount: 6,
  relationshipSharedViewCount: 8,
);

Set<SharedTraitKind> _kinds(DiscoveryCandidate candidate) => {
  for (final t in SharedTraits.between(viewer: _viewer, candidate: candidate))
    t.kind,
};

void main() {
  test('lists every answer both people gave the same way', () {
    expect(
      _kinds(_candidate()),
      containsAll({
        SharedTraitKind.relationshipGoal,
        SharedTraitKind.relationshipQuestions,
        SharedTraitKind.children,
        SharedTraitKind.age,
        SharedTraitKind.smoking,
        SharedTraitKind.drinking,
        SharedTraitKind.partnerExpectations,
        SharedTraitKind.diet,
        SharedTraitKind.weekend,
        SharedTraitKind.interests,
        SharedTraitKind.languages,
        SharedTraitKind.city,
      }),
    );
  });

  test('"prefer not to say" on both sides is not something in common', () {
    expect(_kinds(_candidate()), isNot(contains(SharedTraitKind.pets)));
  });

  test('lists hold only the shared items, in the viewer order', () {
    final traits = SharedTraits.between(
      viewer: _viewer,
      candidate: _candidate(),
    );
    SharedTrait of(SharedTraitKind k) => traits.firstWhere((t) => t.kind == k);
    expect(of(SharedTraitKind.interests).values, ['travel', 'coffee']);
    expect(of(SharedTraitKind.weekend).values, [WeekendPreference.movies]);
    expect(of(SharedTraitKind.relationshipQuestions).values, ['6', '8']);
  });

  test('ages count as close within three years', () {
    expect(_kinds(_candidate(age: 25)), contains(SharedTraitKind.age));
    expect(_kinds(_candidate(age: 24)), isNot(contains(SharedTraitKind.age)));
  });

  test('expectations count only when every stated one is fully met', () {
    // The viewer never wants a smoker; this candidate smokes daily.
    final smoker = _candidate(
      lifestyle: const ProfileLifestyle(
        smoking: OnboardingLifestyleOption.daily,
        partnerDrinkingPref: PartnerPreference.prefer,
      ),
    );
    expect(
      _kinds(smoker),
      isNot(contains(SharedTraitKind.partnerExpectations)),
    );
  });

  testWidgets('the sheet lists what they share instead of repeating reasons', (
    tester,
  ) async {
    const breakdown = CompatibilityBreakdown(
      overallScore: 88,
      relationshipScore: 100,
      interestScore: 70,
      lifestyleScore: 50,
    );
    const reason = CompatibilityReason(
      messageKey: 'compatReasonSameRelationshipGoal',
      category: CompatibilityCategory.relationship,
    );
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('tr'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCompatibilityBreakdownSheet(
              context,
              breakdown: breakdown,
              reasons: const [reason],
              shared: SharedTraits.between(
                viewer: _viewer,
                candidate: _candidate(),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(_tr.sharedTraitsTitle), findsOneWidget);
    expect(
      find.textContaining(
        _tr.sharedTraitQuestionsValue(6, 8),
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(_tr.dietVegetarian, findRichText: true),
      findsOneWidget,
    );
    // The reason line would repeat the shared goal; it is not shown.
    expect(
      find.textContaining(_tr.compatReasonSameRelationshipGoal),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  test('every kind has a title and renders a value in both languages', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      for (final trait in SharedTraits.between(
        viewer: _viewer,
        candidate: _candidate(),
      )) {
        expect(SharedTraitsSection.titleOf(l10n, trait.kind), isNotEmpty);
        expect(SharedTraitsSection.valueOf(l10n, trait).trim(), isNotEmpty);
      }
    }
  });
}
