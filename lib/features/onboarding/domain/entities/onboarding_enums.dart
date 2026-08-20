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
  static const petValues = [none, cat, dog, both, other, preferNotToSay];
}
