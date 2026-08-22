/// Public discovery card. Exact GPS is never included.
class DiscoveryCandidate {
  const DiscoveryCandidate({
    required this.uid,
    required this.displayName,
    required this.age,
    this.photos = const [],
    this.distanceLabel,
    this.distanceKm,
    this.compatibilityScore = 0,
    this.interests = const [],
    this.sharedInterests = const [],
    this.compatibilityReasons = const [],
    this.bio,
    this.city,
    this.gender,
    this.relationshipGoal,
    this.musicCompatibilityScore,
    this.relationshipCompatibilityScore,
    this.relationshipSharedViewCount,
    this.relationshipAlignedCount,
    this.relationshipSummaryTopics = const [],
    this.isDemo = false,
  });

  final String uid;
  final String displayName;
  final int age;
  final List<String> photos;

  /// Primary photo for card thumbnails.
  String? get photoUrl => photos.isEmpty ? null : photos.first;

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
  final String? gender;
  final String? relationshipGoal;

  /// Extra music-taste signal (0–100). Null when neither person has music data.
  /// Never used as the only match criterion.
  final int? musicCompatibilityScore;

  /// Relationship-answer overlap (0–100). Null when there is no shared question.
  /// Distance is never required for this signal. Never an automatic match.
  final int? relationshipCompatibilityScore;
  final int? relationshipSharedViewCount;
  final int? relationshipAlignedCount;
  final List<String> relationshipSummaryTopics;

  /// Local seed profile. Never persisted to production Firestore.
  final bool isDemo;
}
