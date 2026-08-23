import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';

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
    this.compatibilityStatus = CompatibilityDisplayStatus.calculating,
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
    this.isVerified = false,
    this.categoryRelationshipScore,
    this.categoryInterestScore,
    this.categoryLifestyleScore,
    this.categoryQuestionScore,
    this.categoryMusicScore,
    this.categoryCommunicationScore,
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
  final CompatibilityDisplayStatus compatibilityStatus;
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

  /// Profile verified via Sumsub (server-authoritative).
  final bool isVerified;

  /// Category scores from server compatibility breakdown (0–100).
  final int? categoryRelationshipScore;
  final int? categoryInterestScore;
  final int? categoryLifestyleScore;
  final int? categoryQuestionScore;
  final int? categoryMusicScore;
  final int? categoryCommunicationScore;

  bool get hasCompatibilityScore =>
      compatibilityStatus == CompatibilityDisplayStatus.ready &&
      compatibilityScore > 0;

  DiscoveryCandidate copyWith({
    String? uid,
    String? displayName,
    int? age,
    List<String>? photos,
    String? distanceLabel,
    double? distanceKm,
    int? compatibilityScore,
    CompatibilityDisplayStatus? compatibilityStatus,
    List<String>? interests,
    List<String>? sharedInterests,
    List<String>? compatibilityReasons,
    String? bio,
    String? city,
    String? gender,
    String? relationshipGoal,
    int? musicCompatibilityScore,
    int? relationshipCompatibilityScore,
    int? relationshipSharedViewCount,
    int? relationshipAlignedCount,
    List<String>? relationshipSummaryTopics,
    bool? isDemo,
    bool? isVerified,
    int? categoryRelationshipScore,
    int? categoryInterestScore,
    int? categoryLifestyleScore,
    int? categoryQuestionScore,
    int? categoryMusicScore,
    int? categoryCommunicationScore,
  }) {
    return DiscoveryCandidate(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      age: age ?? this.age,
      photos: photos ?? this.photos,
      distanceLabel: distanceLabel ?? this.distanceLabel,
      distanceKm: distanceKm ?? this.distanceKm,
      compatibilityScore: compatibilityScore ?? this.compatibilityScore,
      compatibilityStatus: compatibilityStatus ?? this.compatibilityStatus,
      interests: interests ?? this.interests,
      sharedInterests: sharedInterests ?? this.sharedInterests,
      compatibilityReasons: compatibilityReasons ?? this.compatibilityReasons,
      bio: bio ?? this.bio,
      city: city ?? this.city,
      gender: gender ?? this.gender,
      relationshipGoal: relationshipGoal ?? this.relationshipGoal,
      musicCompatibilityScore:
          musicCompatibilityScore ?? this.musicCompatibilityScore,
      relationshipCompatibilityScore: relationshipCompatibilityScore ??
          this.relationshipCompatibilityScore,
      relationshipSharedViewCount:
          relationshipSharedViewCount ?? this.relationshipSharedViewCount,
      relationshipAlignedCount:
          relationshipAlignedCount ?? this.relationshipAlignedCount,
      relationshipSummaryTopics:
          relationshipSummaryTopics ?? this.relationshipSummaryTopics,
      isDemo: isDemo ?? this.isDemo,
      isVerified: isVerified ?? this.isVerified,
      categoryRelationshipScore:
          categoryRelationshipScore ?? this.categoryRelationshipScore,
      categoryInterestScore:
          categoryInterestScore ?? this.categoryInterestScore,
      categoryLifestyleScore:
          categoryLifestyleScore ?? this.categoryLifestyleScore,
      categoryQuestionScore:
          categoryQuestionScore ?? this.categoryQuestionScore,
      categoryMusicScore: categoryMusicScore ?? this.categoryMusicScore,
      categoryCommunicationScore:
          categoryCommunicationScore ?? this.categoryCommunicationScore,
    );
  }
}
