import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/compatibility/domain/services/mevora_compatibility_engine.dart';
import 'package:mevora/features/discovery/domain/compatibility/compatibility_engine.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_enums.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/services/profile_completion_calculator.dart';

void main() {
  const userA = UserProfile(
    uid: 'a',
    displayName: 'Ada',
    age: 27,
    interests: ['coffee', 'movies', 'travel'],
    languages: ['turkish', 'english'],
    hobbies: ['fitness'],
    heightCm: 178,
    relationshipGoal: OnboardingRelationshipGoal.longTerm,
    lifestyleProfile: ProfileLifestyle(
      smoking: OnboardingLifestyleOption.never,
      drinking: OnboardingLifestyleOption.sometimes,
      partnerSmokingPref: PartnerPreference.never,
      partnerDrinkingPref: PartnerPreference.noIssue,
      childrenPreference: ChildrenPreference.maybe,
    ),
  );

  const userB = UserProfile(
    uid: 'b',
    displayName: 'Burak',
    age: 28,
    interests: ['coffee', 'movies', 'travel'],
    languages: ['turkish', 'english'],
    hobbies: ['fitness'],
    heightCm: 170,
    relationshipGoal: 'longTerm',
    lifestyleProfile: ProfileLifestyle(
      smoking: OnboardingLifestyleOption.never,
      drinking: OnboardingLifestyleOption.sometimes,
      partnerSmokingPref: PartnerPreference.never,
      partnerDrinkingPref: PartnerPreference.noIssue,
      childrenPreference: ChildrenPreference.maybe,
    ),
  );

  const userC = UserProfile(
    uid: 'c',
    displayName: 'Can',
    age: 35,
    interests: ['gaming'],
    languages: ['german'],
    hobbies: ['coding'],
    relationshipGoal: OnboardingRelationshipGoal.friendship,
    lifestyleProfile: ProfileLifestyle(
      smoking: OnboardingLifestyleOption.regularly,
      drinking: OnboardingLifestyleOption.daily,
      partnerSmokingPref: PartnerPreference.noIssue,
      childrenPreference: ChildrenPreference.no,
    ),
  );

  test('similar profiles score higher than mismatched profiles', () {
    final high = MevoraCompatibilityEngine.calculate(
      viewer: userA,
      candidate: userB,
    );
    final low = MevoraCompatibilityEngine.calculate(
      viewer: userA,
      candidate: userC,
    );
    expect(high.overallScore, greaterThan(low.overallScore));
    expect(high.languageScore, isNotNull);
    expect(high.hobbyScore, isNotNull);
    expect(high.overallScore, greaterThan(50));
  });

  test('missing profile fields exclude categories instead of zeroing score', () {
    const sparse = UserProfile(
      uid: 'd',
      displayName: 'Deniz',
      age: 26,
      interests: ['music'],
    );
    final engine = CompatibilityEngine.standard();
    final result = engine.evaluate(
      const CompatibilityContext(viewer: userA, candidate: sparse),
    );
    expect(result.score, greaterThan(0));
    expect(result.categoryScores.containsKey('languages'), isFalse);
    expect(result.categoryScores.containsKey('hobbies'), isFalse);
  });

  test('relationship goal aliases normalize correctly', () {
    expect(
      CompatibilityScoring.normalizeRelationshipGoal('longTerm'),
      OnboardingRelationshipGoal.longTerm,
    );
    expect(
      CompatibilityScoring.normalizeRelationshipGoal('long_term'),
      OnboardingRelationshipGoal.longTerm,
    );
  });

  test('partner smoking preference lowers incompatible matches', () {
    const strict = UserProfile(
      uid: 'e',
      displayName: 'Ece',
      age: 28,
      lifestyleProfile: ProfileLifestyle(
        smoking: OnboardingLifestyleOption.never,
        partnerSmokingPref: PartnerPreference.never,
      ),
    );
    const smoker = UserProfile(
      uid: 'f',
      displayName: 'Fırat',
      age: 29,
      lifestyleProfile: ProfileLifestyle(
        smoking: OnboardingLifestyleOption.regularly,
      ),
    );
    const nonSmoker = UserProfile(
      uid: 'g',
      displayName: 'Gül',
      age: 29,
      lifestyleProfile: ProfileLifestyle(
        smoking: OnboardingLifestyleOption.never,
      ),
    );
    final engine = CompatibilityEngine.standard();
    final againstSmoker = engine.evaluate(
      const CompatibilityContext(viewer: strict, candidate: smoker),
    );
    final againstNonSmoker = engine.evaluate(
      const CompatibilityContext(viewer: strict, candidate: nonSmoker),
    );
    expect(againstNonSmoker.score, greaterThan(againstSmoker.score));
  });

  test('profile completion handles legacy sparse users safely', () {
    const legacy = UserProfile(
      uid: 'legacy',
      displayName: 'Legacy',
      age: 30,
      interests: ['music', 'travel', 'food'],
      relationshipGoal: OnboardingRelationshipGoal.longTerm,
    );
    final completion = ProfileCompletionCalculator.calculate(legacy);
    expect(completion.percent, lessThan(100));
    expect(completion.percent, greaterThan(0));
  });

  test('multi-select overlap uses jaccard similarity', () {
    final score = CompatibilityScoring.jaccard(
      {'coffee', 'movies', 'travel'},
      {'coffee', 'movies', 'music'},
    );
    expect(score, closeTo(0.5, 0.01));
  });
}
