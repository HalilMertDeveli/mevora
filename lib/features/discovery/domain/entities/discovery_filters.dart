/// UI-only discovery filters. Backend filtering arrives in a later phase.
class DiscoveryFilters {
  const DiscoveryFilters({
    this.minAge = 18,
    this.maxAge = 45,
    this.maxDistanceKm = 50,
    this.gender,
    this.relationshipGoal,
  });

  final int minAge;
  final int maxAge;
  final double maxDistanceKm;
  final String? gender;
  final String? relationshipGoal;

  DiscoveryFilters copyWith({
    int? minAge,
    int? maxAge,
    double? maxDistanceKm,
    String? gender,
    bool clearGender = false,
    String? relationshipGoal,
    bool clearRelationshipGoal = false,
  }) {
    return DiscoveryFilters(
      minAge: minAge ?? this.minAge,
      maxAge: maxAge ?? this.maxAge,
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      gender: clearGender ? null : (gender ?? this.gender),
      relationshipGoal: clearRelationshipGoal
          ? null
          : (relationshipGoal ?? this.relationshipGoal),
    );
  }
}
