/// Structured lifestyle fields for profiles and onboarding.
class ProfileLifestyle {
  const ProfileLifestyle({
    this.smoking,
    this.drinking,
    this.exercise,
    this.pets,
    this.partnerSmokingPref,
    this.partnerDrinkingPref,
    this.childrenPreference,
    this.partnerChildrenPref,
    this.socialRhythm,
    this.socialLevel,
    this.weekendPreferences = const [],
    this.cohabitationPreference,
  });

  final String? smoking;
  final String? drinking;
  final String? exercise;
  final String? pets;
  final String? partnerSmokingPref;
  final String? partnerDrinkingPref;
  final String? childrenPreference;
  final String? partnerChildrenPref;
  final String? socialRhythm;
  final String? socialLevel;
  final List<String> weekendPreferences;
  final String? cohabitationPreference;

  bool get isEmpty =>
      (smoking == null || smoking!.isEmpty) &&
      (drinking == null || drinking!.isEmpty) &&
      (exercise == null || exercise!.isEmpty) &&
      (pets == null || pets!.isEmpty) &&
      (partnerSmokingPref == null || partnerSmokingPref!.isEmpty) &&
      (partnerDrinkingPref == null || partnerDrinkingPref!.isEmpty) &&
      (childrenPreference == null || childrenPreference!.isEmpty) &&
      (partnerChildrenPref == null || partnerChildrenPref!.isEmpty) &&
      (socialRhythm == null || socialRhythm!.isEmpty) &&
      (socialLevel == null || socialLevel!.isEmpty) &&
      weekendPreferences.isEmpty &&
      (cohabitationPreference == null || cohabitationPreference!.isEmpty);

  ProfileLifestyle copyWith({
    String? smoking,
    String? drinking,
    String? exercise,
    String? pets,
    String? partnerSmokingPref,
    String? partnerDrinkingPref,
    String? childrenPreference,
    String? partnerChildrenPref,
    String? socialRhythm,
    String? socialLevel,
    List<String>? weekendPreferences,
    String? cohabitationPreference,
  }) {
    return ProfileLifestyle(
      smoking: smoking ?? this.smoking,
      drinking: drinking ?? this.drinking,
      exercise: exercise ?? this.exercise,
      pets: pets ?? this.pets,
      partnerSmokingPref: partnerSmokingPref ?? this.partnerSmokingPref,
      partnerDrinkingPref: partnerDrinkingPref ?? this.partnerDrinkingPref,
      childrenPreference: childrenPreference ?? this.childrenPreference,
      partnerChildrenPref: partnerChildrenPref ?? this.partnerChildrenPref,
      socialRhythm: socialRhythm ?? this.socialRhythm,
      socialLevel: socialLevel ?? this.socialLevel,
      weekendPreferences: weekendPreferences ?? this.weekendPreferences,
      cohabitationPreference:
          cohabitationPreference ?? this.cohabitationPreference,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (smoking != null) 'smoking': smoking,
      if (drinking != null) 'drinking': drinking,
      if (exercise != null) 'exercise': exercise,
      if (pets != null) 'pets': pets,
      if (partnerSmokingPref != null) 'partnerSmokingPref': partnerSmokingPref,
      if (partnerDrinkingPref != null)
        'partnerDrinkingPref': partnerDrinkingPref,
      if (childrenPreference != null) 'childrenPreference': childrenPreference,
      if (partnerChildrenPref != null)
        'partnerChildrenPref': partnerChildrenPref,
      if (socialRhythm != null) 'socialRhythm': socialRhythm,
      if (socialLevel != null) 'socialLevel': socialLevel,
      if (weekendPreferences.isNotEmpty) 'weekendPreferences': weekendPreferences,
      if (cohabitationPreference != null)
        'cohabitationPreference': cohabitationPreference,
    };
  }

  factory ProfileLifestyle.fromMap(Object? value) {
    if (value is! Map) {
      return const ProfileLifestyle();
    }
    return ProfileLifestyle(
      smoking: value['smoking'] as String?,
      drinking: value['drinking'] as String?,
      exercise: value['exercise'] as String?,
      pets: value['pets'] as String?,
      partnerSmokingPref: value['partnerSmokingPref'] as String?,
      partnerDrinkingPref: value['partnerDrinkingPref'] as String?,
      childrenPreference: value['childrenPreference'] as String?,
      partnerChildrenPref: value['partnerChildrenPref'] as String?,
      socialRhythm: value['socialRhythm'] as String?,
      socialLevel: value['socialLevel'] as String?,
      weekendPreferences: _stringList(value['weekendPreferences']),
      cohabitationPreference: value['cohabitationPreference'] as String?,
    );
  }

  /// Tags for the compatibility engine's legacy list format.
  List<String> toTags() {
    return [
      if (smoking != null && smoking!.isNotEmpty) 'smoking:$smoking',
      if (drinking != null && drinking!.isNotEmpty) 'drinking:$drinking',
      if (exercise != null && exercise!.isNotEmpty) 'exercise:$exercise',
      if (pets != null && pets!.isNotEmpty) 'pets:$pets',
      if (socialRhythm != null && socialRhythm!.isNotEmpty)
        'socialRhythm:$socialRhythm',
      if (socialLevel != null && socialLevel!.isNotEmpty)
        'socialLevel:$socialLevel',
      for (final pref in weekendPreferences) 'weekend:$pref',
      if (cohabitationPreference != null && cohabitationPreference!.isNotEmpty)
        'cohabitation:$cohabitationPreference',
    ];
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return [
      for (final item in value)
        if (item is String && item.isNotEmpty) item,
    ];
  }
}
