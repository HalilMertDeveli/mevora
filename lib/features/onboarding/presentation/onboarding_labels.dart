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

  /// Alcohol / drinking labels.
  ///
  /// Keeps smoking/exercise labels intact while rendering `ProfileLifestyle.drinking`
  /// with the requested UI option set.
  static String alcohol(AppLocalizations l10n, String? value) {
    return switch (value) {
      OnboardingLifestyleOption.never => l10n.onboardingAlcoholNone,
      OnboardingLifestyleOption.sometimes => l10n.onboardingAlcoholRarely,
      OnboardingLifestyleOption.regularly => l10n.onboardingAlcoholSocial,
      OnboardingLifestyleOption.alcoholSpecialOccasion =>
        l10n.onboardingAlcoholSpecialOccasion,
      OnboardingLifestyleOption.daily => l10n.onboardingAlcoholFrequently,
      // Backward compatibility: legacy value that previously existed for drinking.
      OnboardingLifestyleOption.preferNotToSay =>
        l10n.onboardingEducationPreferNotToSay,
      _ => value ?? '—',
    };
  }

  static String language(AppLocalizations l10n, String id) {
    return switch (id) {
      'turkish' => l10n.languageTurkish,
      'english' => l10n.languageEnglish,
      'german' => l10n.languageGerman,
      'french' => l10n.languageFrench,
      'spanish' => l10n.languageSpanish,
      'italian' => l10n.languageItalian,
      'russian' => l10n.languageRussian,
      'arabic' => l10n.languageArabic,
      'persian' => l10n.languagePersian,
      'kurdish' => l10n.languageKurdish,
      'greek' => l10n.languageGreek,
      'dutch' => l10n.languageDutch,
      'portuguese' => l10n.languagePortuguese,
      'chinese' => l10n.languageChinese,
      'japanese' => l10n.languageJapanese,
      'korean' => l10n.languageKorean,
      _ => id,
    };
  }

  static String hobby(AppLocalizations l10n, String id) {
    return switch (id) {
      'working_out' => l10n.hobbyWorkingOut,
      'running' => l10n.hobbyRunning,
      'fitness' => l10n.hobbyFitness,
      'swimming' => l10n.hobbySwimming,
      'dancing' => l10n.hobbyDancing,
      'photography' => l10n.hobbyPhotography,
      'painting' => l10n.hobbyPainting,
      'gaming' => l10n.hobbyGaming,
      'coding' => l10n.hobbyCoding,
      'cooking' => l10n.hobbyCooking,
      'travel' => l10n.hobbyTravel,
      'camping' => l10n.hobbyCamping,
      'hiking' => l10n.hobbyHiking,
      'playing_instrument' => l10n.hobbyPlayingInstrument,
      'reading' => l10n.hobbyReading,
      'yoga' => l10n.hobbyYoga,
      'cycling' => l10n.hobbyCycling,
      'team_sports' => l10n.hobbyTeamSports,
      _ => id,
    };
  }

  static String partnerPreference(AppLocalizations l10n, String? value) {
    return switch (value) {
      PartnerPreference.noIssue => l10n.partnerPrefNoIssue,
      PartnerPreference.prefer => l10n.partnerPrefPrefer,
      PartnerPreference.preferNot => l10n.partnerPrefPreferNot,
      PartnerPreference.never => l10n.partnerPrefNever,
      _ => value ?? '—',
    };
  }

  static String childrenPreference(AppLocalizations l10n, String? value) {
    return switch (value) {
      ChildrenPreference.yes => l10n.childrenPrefYes,
      ChildrenPreference.no => l10n.childrenPrefNo,
      ChildrenPreference.maybe => l10n.childrenPrefMaybe,
      ChildrenPreference.undecided => l10n.childrenPrefUndecided,
      ChildrenPreference.preferNotToSay => l10n.onboardingEducationPreferNotToSay,
      _ => value ?? '—',
    };
  }

  static String socialRhythm(AppLocalizations l10n, String? value) {
    return switch (value) {
      SocialRhythm.morning => l10n.socialRhythmMorning,
      SocialRhythm.night => l10n.socialRhythmNight,
      SocialRhythm.varies => l10n.socialRhythmVaries,
      _ => value ?? '—',
    };
  }

  static String socialLevel(AppLocalizations l10n, String? value) {
    return switch (value) {
      SocialLevel.verySocial => l10n.socialLevelVerySocial,
      SocialLevel.balanced => l10n.socialLevelBalanced,
      SocialLevel.quiet => l10n.socialLevelQuiet,
      _ => value ?? '—',
    };
  }

  static String weekendPreference(AppLocalizations l10n, String id) {
    return switch (id) {
      WeekendPreference.friendsOut => l10n.weekendFriendsOut,
      WeekendPreference.homeRelax => l10n.weekendHomeRelax,
      WeekendPreference.sports => l10n.weekendSports,
      WeekendPreference.travel => l10n.weekendTravel,
      WeekendPreference.nature => l10n.weekendNature,
      WeekendPreference.party => l10n.weekendParty,
      WeekendPreference.family => l10n.weekendFamily,
      WeekendPreference.movies => l10n.weekendMovies,
      _ => id,
    };
  }

  static String cohabitation(AppLocalizations l10n, String? value) {
    return switch (value) {
      CohabitationPreference.yes => l10n.cohabitationYes,
      CohabitationPreference.maybeLater => l10n.cohabitationMaybeLater,
      CohabitationPreference.unsure => l10n.cohabitationUnsure,
      CohabitationPreference.no => l10n.cohabitationNo,
      CohabitationPreference.preferNotToSay =>
        l10n.onboardingEducationPreferNotToSay,
      _ => value ?? '—',
    };
  }
}
