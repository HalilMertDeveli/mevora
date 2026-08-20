/// Structured lifestyle fields for profiles and onboarding.
class ProfileLifestyle {
  const ProfileLifestyle({
    this.smoking,
    this.drinking,
    this.exercise,
    this.pets,
  });

  final String? smoking;
  final String? drinking;
  final String? exercise;
  final String? pets;

  bool get isEmpty =>
      (smoking == null || smoking!.isEmpty) &&
      (drinking == null || drinking!.isEmpty) &&
      (exercise == null || exercise!.isEmpty) &&
      (pets == null || pets!.isEmpty);

  ProfileLifestyle copyWith({
    String? smoking,
    String? drinking,
    String? exercise,
    String? pets,
  }) {
    return ProfileLifestyle(
      smoking: smoking ?? this.smoking,
      drinking: drinking ?? this.drinking,
      exercise: exercise ?? this.exercise,
      pets: pets ?? this.pets,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (smoking != null) 'smoking': smoking,
      if (drinking != null) 'drinking': drinking,
      if (exercise != null) 'exercise': exercise,
      if (pets != null) 'pets': pets,
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
    );
  }

  /// Tags for the compatibility engine's legacy list format.
  List<String> toTags() {
    return [
      if (smoking != null && smoking!.isNotEmpty) 'smoking:$smoking',
      if (drinking != null && drinking!.isNotEmpty) 'drinking:$drinking',
      if (exercise != null && exercise!.isNotEmpty) 'exercise:$exercise',
      if (pets != null && pets!.isNotEmpty) 'pets:$pets',
    ];
  }
}
