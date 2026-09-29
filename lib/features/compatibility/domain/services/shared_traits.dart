import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/discovery/domain/compatibility/compatibility_engine.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_enums.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

/// Something two people answered the same way, or that fits both.
enum SharedTraitKind {
  relationshipGoal,
  relationshipQuestions,
  children,
  age,
  smoking,
  drinking,
  partnerExpectations,
  exercise,
  diet,
  pets,
  rhythm,
  socialLevel,
  livingTogether,
  weekend,
  interests,
  hobbies,
  languages,
  city,
}

class SharedTrait {
  const SharedTrait(this.kind, {this.value, this.values = const []});

  final SharedTraitKind kind;

  /// The shared single answer (a stored option id), when there is one.
  final String? value;

  /// Shared list items, or two numbers (ages, aligned/shared questions).
  final List<String> values;
}

/// What a viewer and a candidate have in common, from the answers both gave.
///
/// Only exact agreement counts: two people who both chose "prefer not to
/// say" share nothing, and an answer one of them skipped is never guessed.
/// Humor is not here on purpose: before a match the candidate's humor profile
/// is private, and only the match-level compatibility may reveal it.
abstract final class SharedTraits {
  /// Ages this close read as "about the same age".
  static const int closeAgeGap = 3;

  static List<SharedTrait> between({
    required UserProfile viewer,
    required DiscoveryCandidate candidate,
    CompatibilityBreakdown? breakdown,
  }) {
    final mine = viewer.lifestyleProfile;
    final theirs = candidate.lifestyleProfile;
    final traits = <SharedTrait>[];

    void same(SharedTraitKind kind, String? a, String? b) {
      if (_answered(a) && a == b) {
        traits.add(SharedTrait(kind, value: a));
      }
    }

    void overlap(SharedTraitKind kind, List<String> a, List<String> b) {
      final theirSet = b.map(_norm).toSet();
      final both = [
        for (final item in a)
          if (theirSet.contains(_norm(item))) item,
      ];
      if (both.isNotEmpty) {
        traits.add(SharedTrait(kind, values: both));
      }
    }

    same(
      SharedTraitKind.relationshipGoal,
      viewer.relationshipGoal,
      candidate.relationshipGoal,
    );

    final aligned =
        candidate.relationshipAlignedCount ?? breakdown?.questionAlignedCount;
    final asked =
        candidate.relationshipSharedViewCount ?? breakdown?.questionSharedCount;
    if (aligned != null && asked != null && aligned > 0 && asked > 0) {
      traits.add(
        SharedTrait(
          SharedTraitKind.relationshipQuestions,
          values: ['$aligned', '$asked'],
        ),
      );
    }

    same(
      SharedTraitKind.children,
      mine.childrenPreference,
      theirs.childrenPreference,
    );

    final myAge = viewer.age;
    if (myAge != null &&
        myAge > 0 &&
        candidate.age > 0 &&
        (myAge - candidate.age).abs() <= closeAgeGap) {
      traits.add(
        SharedTrait(
          SharedTraitKind.age,
          values: ['$myAge', '${candidate.age}'],
        ),
      );
    }

    same(SharedTraitKind.smoking, mine.smoking, theirs.smoking);
    same(SharedTraitKind.drinking, mine.drinking, theirs.drinking);
    if (_expectationsFit(mine, theirs)) {
      traits.add(const SharedTrait(SharedTraitKind.partnerExpectations));
    }
    same(SharedTraitKind.exercise, mine.exercise, theirs.exercise);
    same(SharedTraitKind.diet, mine.diet, theirs.diet);
    same(SharedTraitKind.pets, mine.pets, theirs.pets);
    same(SharedTraitKind.rhythm, mine.socialRhythm, theirs.socialRhythm);
    same(SharedTraitKind.socialLevel, mine.socialLevel, theirs.socialLevel);
    same(
      SharedTraitKind.livingTogether,
      mine.cohabitationPreference,
      theirs.cohabitationPreference,
    );
    overlap(
      SharedTraitKind.weekend,
      mine.weekendPreferences,
      theirs.weekendPreferences,
    );
    overlap(
      SharedTraitKind.interests,
      viewer.interests,
      candidate.sharedInterests.isNotEmpty
          ? candidate.sharedInterests
          : candidate.interests,
    );
    overlap(SharedTraitKind.hobbies, viewer.hobbies, candidate.hobbies);
    overlap(SharedTraitKind.languages, viewer.languages, candidate.languages);

    final myCity = viewer.city?.trim();
    final theirCity = candidate.city?.trim();
    if (myCity != null &&
        myCity.isNotEmpty &&
        theirCity != null &&
        _norm(myCity) == _norm(theirCity)) {
      traits.add(SharedTrait(SharedTraitKind.city, value: theirCity));
    }
    return traits;
  }

  /// Each person's smoking and drinking fit what the other asked for. Needs
  /// at least one real expectation ("no issue" says nothing), and every
  /// expectation that was given must be fully met.
  static bool _expectationsFit(ProfileLifestyle mine, ProfileLifestyle theirs) {
    final checks = <(String?, String?)>[
      (theirs.smoking, mine.partnerSmokingPref),
      (theirs.drinking, mine.partnerDrinkingPref),
      (mine.smoking, theirs.partnerSmokingPref),
      (mine.drinking, theirs.partnerDrinkingPref),
    ];
    var meaningful = 0;
    for (final (habit, pref) in checks) {
      final level = CompatibilityScoring.habitLevel(habit);
      if (level == null || pref == null || pref.isEmpty) {
        continue;
      }
      if (CompatibilityScoring.partnerHabitScore(level, pref) < 1) {
        return false;
      }
      if (pref != PartnerPreference.noIssue) {
        meaningful++;
      }
    }
    return meaningful > 0;
  }

  static bool _answered(String? value) =>
      value != null &&
      value.isNotEmpty &&
      value != OnboardingLifestyleOption.preferNotToSay;

  static String _norm(String value) => value.trim().toLowerCase();
}
