/// Public discovery card. Exact GPS is never included.
class DiscoveryCandidate {
  const DiscoveryCandidate({
    required this.uid,
    required this.displayName,
    required this.age,
    this.photoUrl,
    this.distanceLabel,
    this.distanceKm,
    this.compatibilityScore = 0,
    this.interests = const [],
    this.sharedInterests = const [],
    this.compatibilityReasons = const [],
    this.bio,
    this.city,
  });

  final String uid;
  final String displayName;
  final int age;
  final String? photoUrl;

  /// Derived server label such as "3.8 km away".
  final String? distanceLabel;

  /// Derived kilometers. Never a coordinate pair.
  final double? distanceKm;
  final int compatibilityScore;
  final List<String> interests;
  final List<String> sharedInterests;
  final List<String> compatibilityReasons;
  final String? bio;
  final String? city;
}
