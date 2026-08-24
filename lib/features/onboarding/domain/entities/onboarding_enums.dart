abstract final class OnboardingGender {
  static const man = 'man';
  static const woman = 'woman';
  static const nonBinary = 'non_binary';

  static const values = [man, woman, nonBinary];
}

abstract final class OnboardingInterestedIn {
  static const men = 'men';
  static const women = 'women';
  static const everyone = 'everyone';

  static const values = [men, women, everyone];
}

abstract final class OnboardingEducation {
  static const highSchool = 'high_school';
  static const someCollege = 'some_college';
  static const bachelors = 'bachelors';
  static const masters = 'masters';
  static const phd = 'phd';
  static const preferNotToSay = 'prefer_not_to_say';

  static const values = [
    highSchool,
    someCollege,
    bachelors,
    masters,
    phd,
    preferNotToSay,
  ];
}

abstract final class OnboardingRelationshipGoal {
  static const longTerm = 'long_term';
  static const shortTerm = 'short_term';
  static const friendship = 'friendship';
  static const notSure = 'not_sure';
  static const preferNotToSay = 'prefer_not_to_say';

  static const values = [
    longTerm,
    shortTerm,
    friendship,
    notSure,
    preferNotToSay,
  ];
}

abstract final class OnboardingLifestyleOption {
  static const never = 'never';
  static const sometimes = 'sometimes';
  static const regularly = 'regularly';
  static const daily = 'daily';
  static const preferNotToSay = 'prefer_not_to_say';
  static const none = 'none';
  static const cat = 'cat';
  static const dog = 'dog';
  static const both = 'both';
  static const other = 'other';

  static const habitValues = [never, sometimes, regularly, daily, preferNotToSay];

  // Alcohol options (drinking). Values are normalized strings stored in
  // `ProfileLifestyle.drinking`.
  static const alcoholSpecialOccasion = 'alcohol_special_occasion';
  static const drinkingValues = [
    never, // Hiç kullanmıyorum
    sometimes, // Nadiren
    regularly, // Sosyal olarak
    alcoholSpecialOccasion, // Özel günlerde
    daily, // Sık sık
  ];
  static const petValues = [none, cat, dog, both, other, preferNotToSay];
}

abstract final class PartnerPreference {
  static const noIssue = 'no_issue';
  static const prefer = 'prefer';
  static const preferNot = 'prefer_not';
  static const never = 'never';

  static const values = [noIssue, prefer, preferNot, never];
}

abstract final class ChildrenPreference {
  static const yes = 'yes';
  static const no = 'no';
  static const maybe = 'maybe';
  static const undecided = 'undecided';
  static const preferNotToSay = 'prefer_not_to_say';

  static const values = [yes, no, maybe, undecided, preferNotToSay];
}

abstract final class SocialRhythm {
  static const morning = 'morning';
  static const night = 'night';
  static const varies = 'varies';

  static const values = [morning, night, varies];
}

abstract final class SocialLevel {
  static const verySocial = 'very_social';
  static const balanced = 'balanced';
  static const quiet = 'quiet';

  static const values = [verySocial, balanced, quiet];
}

abstract final class WeekendPreference {
  static const friendsOut = 'friends_out';
  static const homeRelax = 'home_relax';
  static const sports = 'sports';
  static const travel = 'travel';
  static const nature = 'nature';
  static const party = 'party';
  static const family = 'family';
  static const movies = 'movies';

  static const values = [
    friendsOut,
    homeRelax,
    sports,
    travel,
    nature,
    party,
    family,
    movies,
  ];
}

abstract final class CohabitationPreference {
  static const yes = 'yes';
  static const maybeLater = 'maybe_later';
  static const unsure = 'unsure';
  static const no = 'no';
  static const preferNotToSay = 'prefer_not_to_say';

  static const values = [yes, maybeLater, unsure, no, preferNotToSay];
}
