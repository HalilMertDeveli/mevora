import 'package:mevora/features/onboarding/domain/entities/onboarding_enums.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Shared onboarding/profile field labels — single source for onboarding + edit.
abstract final class OnboardingLabels {
  static String gender(AppLocalizations l10n, String? value) {
    return switch (value) {
      OnboardingGender.man => l10n.onboardingGenderMan,
      OnboardingGender.woman => l10n.onboardingGenderWoman,
      OnboardingGender.nonBinary => l10n.onboardingGenderNonBinary,
      _ => value ?? '—',
    };
  }

  static String interestedIn(AppLocalizations l10n, String? value) {
    return switch (value) {
      OnboardingInterestedIn.men => l10n.onboardingInterestedMen,
      OnboardingInterestedIn.women => l10n.onboardingInterestedWomen,
      OnboardingInterestedIn.everyone => l10n.onboardingInterestedEveryone,
      _ => value ?? '—',
    };
  }

  static String interest(AppLocalizations l10n, String id) {
    return switch (id) {
      'music' => l10n.interestMusic,
      'travel' => l10n.interestTravel,
      'fitness' => l10n.interestFitness,
      'food' => l10n.interestFood,
      'art' => l10n.interestArt,
      'movies' => l10n.interestMovies,
      'books' => l10n.interestBooks,
      'gaming' => l10n.interestGaming,
      'nature' => l10n.interestNature,
      'photography' => l10n.interestPhotography,
      'coffee' => l10n.interestCoffee,
      'dancing' => l10n.interestDancing,
      'yoga' => l10n.interestYoga,
      'tech' => l10n.interestTech,
      'fashion' => l10n.interestFashion,
      'pets' => l10n.interestPets,
      'sports' => l10n.interestSports,
      'cooking' => l10n.interestCooking,
      _ => id,
    };
  }

  static String education(AppLocalizations l10n, String? value) {
    return switch (value) {
      OnboardingEducation.highSchool => l10n.onboardingEducationHighSchool,
      OnboardingEducation.someCollege => l10n.onboardingEducationSomeCollege,
      OnboardingEducation.bachelors => l10n.onboardingEducationBachelors,
      OnboardingEducation.masters => l10n.onboardingEducationMasters,
      OnboardingEducation.phd => l10n.onboardingEducationPhd,
      OnboardingEducation.preferNotToSay =>
        l10n.onboardingEducationPreferNotToSay,
      _ => value ?? '—',
    };
  }

  static String relationshipGoal(AppLocalizations l10n, String? value) {
    return switch (value) {
      OnboardingRelationshipGoal.longTerm =>
        l10n.onboardingRelationshipLongTerm,
      OnboardingRelationshipGoal.shortTerm =>
        l10n.onboardingRelationshipShortTerm,
      OnboardingRelationshipGoal.friendship =>
        l10n.onboardingRelationshipFriendship,
      OnboardingRelationshipGoal.notSure => l10n.onboardingRelationshipNotSure,
      OnboardingRelationshipGoal.preferNotToSay =>
        l10n.onboardingRelationshipPreferNotToSay,
      _ => value ?? '—',
    };
  }

  static String lifestyle(AppLocalizations l10n, String? value) {
    return switch (value) {
      OnboardingLifestyleOption.never => l10n.onboardingLifestyleNever,
      OnboardingLifestyleOption.sometimes => l10n.onboardingLifestyleSometimes,
      OnboardingLifestyleOption.regularly => l10n.onboardingLifestyleRegularly,
      OnboardingLifestyleOption.daily => l10n.onboardingLifestyleDaily,
      OnboardingLifestyleOption.none => l10n.onboardingLifestyleNone,
      OnboardingLifestyleOption.cat => l10n.onboardingLifestyleCat,
      OnboardingLifestyleOption.dog => l10n.onboardingLifestyleDog,
      OnboardingLifestyleOption.both => l10n.onboardingLifestyleBoth,
      OnboardingLifestyleOption.other => l10n.onboardingLifestyleOther,
      OnboardingLifestyleOption.preferNotToSay =>
        l10n.onboardingEducationPreferNotToSay,
      _ => value ?? '—',
    };
  }
}
