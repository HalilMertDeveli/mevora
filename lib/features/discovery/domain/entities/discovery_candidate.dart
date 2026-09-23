import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/music/domain/services/music_compatibility.dart';
import 'package:mevora/features/music/domain/entities/public_music_profile.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';

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
    this.languages = const [],
    this.hobbies = const [],
    this.lifestyle = const [],
    this.lifestyleProfile = const ProfileLifestyle(),
    this.sharedInterests = const [],
    this.compatibilityReasons = const [],
    this.bio,
    this.city,
    this.gender,
    this.relationshipGoal,
    this.musicCompatibilityScore,
    this.sharedMusicTracks = const [],
    this.sharedMusicArtists = const [],
    this.sharedMusicGenres = const [],
    this.sharedMusicTrackCount,
    this.sharedMusicArtistCount,
    this.sharedMusicGenreCount,
    this.sharedMusicPlaylistTrackCount,
    this.sharedMusicRecentTrackCount,
    this.musicInsights = const [],
    this.publicMusic = PublicMusicProfile.hidden,
    this.relationshipCompatibilityScore,
    this.relationshipSharedViewCount,
    this.relationshipAlignedCount,
    this.relationshipSummaryTopics = const [],
    this.isDemo = false,
    this.isVerified = false,
    this.isBoosted = false,
    this.categoryRelationshipScore,
    this.categoryInterestScore,
    this.categoryLifestyleScore,
    this.categoryQuestionScore,
    this.categoryMusicScore,
    this.categoryCommunicationScore,
  });

  final String uid;

  /// The Music Taste this member chose to publish. Their imported taste
  /// stays in their own documents and never reaches a candidate card.
  final PublicMusicProfile publicMusic;

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
  final List<String> languages;
  final List<String> hobbies;
  final List<String> lifestyle;
  final ProfileLifestyle lifestyleProfile;
  final List<String> sharedInterests;
  final List<String> compatibilityReasons;
  final String? bio;
  final String? city;
  final String? gender;
  final String? relationshipGoal;

  /// Extra music-taste signal (0–100). Null when neither person has music data.
  /// Never used as the only match criterion.
  final int? musicCompatibilityScore;

  /// Display names for shared tracks / artists (from cached music profiles).
  final List<String> sharedMusicTracks;
  final List<String> sharedMusicArtists;
  final List<String> sharedMusicGenres;
  final int? sharedMusicTrackCount;
  final int? sharedMusicArtistCount;
  final int? sharedMusicGenreCount;
  final int? sharedMusicPlaylistTrackCount;
  final int? sharedMusicRecentTrackCount;
  final List<MusicInsight> musicInsights;

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

  /// Server-authoritative Boost spotlight on this profile card.
  final bool isBoosted;

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

  bool get hasMusicMatchDetail =>
      musicCompatibilityScore != null && musicCompatibilityScore! > 0;

  /// True when the server sent all three core category scores for the sheet UI.
  bool get hasCompleteCoreCategoryBreakdown =>
      categoryRelationshipScore != null &&
      categoryInterestScore != null &&
      categoryLifestyleScore != null;

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
    List<String>? languages,
    List<String>? hobbies,
    List<String>? lifestyle,
    ProfileLifestyle? lifestyleProfile,
    List<String>? sharedInterests,
    List<String>? compatibilityReasons,
    String? bio,
    String? city,
    String? gender,
    String? relationshipGoal,
    int? musicCompatibilityScore,
    List<String>? sharedMusicTracks,
    List<String>? sharedMusicArtists,
    List<String>? sharedMusicGenres,
    int? sharedMusicTrackCount,
    int? sharedMusicArtistCount,
    int? sharedMusicGenreCount,
    int? sharedMusicPlaylistTrackCount,
    int? sharedMusicRecentTrackCount,
    List<MusicInsight>? musicInsights,
    int? relationshipCompatibilityScore,
    int? relationshipSharedViewCount,
    int? relationshipAlignedCount,
    List<String>? relationshipSummaryTopics,
    bool? isDemo,
    bool? isVerified,
    bool? isBoosted,
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
      languages: languages ?? this.languages,
      hobbies: hobbies ?? this.hobbies,
      lifestyle: lifestyle ?? this.lifestyle,
      lifestyleProfile: lifestyleProfile ?? this.lifestyleProfile,
      sharedInterests: sharedInterests ?? this.sharedInterests,
      compatibilityReasons: compatibilityReasons ?? this.compatibilityReasons,
      bio: bio ?? this.bio,
      city: city ?? this.city,
      gender: gender ?? this.gender,
      relationshipGoal: relationshipGoal ?? this.relationshipGoal,
      musicCompatibilityScore:
          musicCompatibilityScore ?? this.musicCompatibilityScore,
      sharedMusicTracks: sharedMusicTracks ?? this.sharedMusicTracks,
      sharedMusicArtists: sharedMusicArtists ?? this.sharedMusicArtists,
      sharedMusicGenres: sharedMusicGenres ?? this.sharedMusicGenres,
      sharedMusicTrackCount:
          sharedMusicTrackCount ?? this.sharedMusicTrackCount,
      sharedMusicArtistCount:
          sharedMusicArtistCount ?? this.sharedMusicArtistCount,
      sharedMusicGenreCount:
          sharedMusicGenreCount ?? this.sharedMusicGenreCount,
      sharedMusicPlaylistTrackCount: sharedMusicPlaylistTrackCount ??
          this.sharedMusicPlaylistTrackCount,
      sharedMusicRecentTrackCount:
          sharedMusicRecentTrackCount ?? this.sharedMusicRecentTrackCount,
      musicInsights: musicInsights ?? this.musicInsights,
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
      isBoosted: isBoosted ?? this.isBoosted,
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
