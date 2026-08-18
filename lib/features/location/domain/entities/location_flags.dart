class LocationFlags {
  const LocationFlags({
    required this.uid,
    this.locationEnabled = false,
    this.locationOnboardingCompleted = false,
    this.lastLocationUpdate,
  });

  final String uid;
  final bool locationEnabled;
  final bool locationOnboardingCompleted;
  final DateTime? lastLocationUpdate;

  LocationFlags copyWith({
    String? uid,
    bool? locationEnabled,
    bool? locationOnboardingCompleted,
    DateTime? lastLocationUpdate,
    bool clearLastLocationUpdate = false,
  }) {
    return LocationFlags(
      uid: uid ?? this.uid,
      locationEnabled: locationEnabled ?? this.locationEnabled,
      locationOnboardingCompleted:
          locationOnboardingCompleted ?? this.locationOnboardingCompleted,
      lastLocationUpdate: clearLastLocationUpdate
          ? null
          : lastLocationUpdate ?? this.lastLocationUpdate,
    );
  }
}
