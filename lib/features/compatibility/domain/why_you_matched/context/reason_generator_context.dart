import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

/// Optional music overlap details beyond [CompatibilityBreakdown.musicScore].
///
/// Populated from discovery / match music payloads — never invented.
class WhyYouMatchedMusicSignals {
  const WhyYouMatchedMusicSignals({
    this.sharedArtists = const [],
    this.sharedTracks = const [],
    this.sharedGenres = const [],
    this.sharedArtistCount,
    this.sharedTrackCount,
    this.sharedGenreCount,
  });

  final List<String> sharedArtists;
  final List<String> sharedTracks;
  final List<String> sharedGenres;
  final int? sharedArtistCount;
  final int? sharedTrackCount;
  final int? sharedGenreCount;

  int get resolvedArtistCount =>
      sharedArtistCount ?? sharedArtists.length;

  int get resolvedTrackCount => sharedTrackCount ?? sharedTracks.length;

  int get resolvedGenreCount => sharedGenreCount ?? sharedGenres.length;

  bool get hasAnyOverlap =>
      resolvedArtistCount > 0 ||
      resolvedTrackCount > 0 ||
      resolvedGenreCount > 0;
}

/// Optional relationship Q&A detail beyond breakdown counts.
class WhyYouMatchedQuestionSignals {
  const WhyYouMatchedQuestionSignals({
    this.topTopics = const [],
  });

  final List<String> topTopics;
}

/// Humor-tagged relationship answer maps for measurable N-of-M evidence.
///
/// Keys are questionIds, values are answerIds. Only humor-catalog questions
/// are compared (see [HumorAnswerComparator.isHumorQuestion]).
class WhyYouMatchedHumorAnswerSignals {
  const WhyYouMatchedHumorAnswerSignals({
    this.viewerAnswers = const {},
    this.candidateAnswers = const {},
  });

  final Map<String, String> viewerAnswers;
  final Map<String, String> candidateAnswers;

  bool get hasAnyAnswers =>
      viewerAnswers.isNotEmpty || candidateAnswers.isNotEmpty;
}

/// Input for [ReasonGenerator] implementations.
///
/// Only fields backed by Phase 0 data sources.
class ReasonGeneratorContext {
  const ReasonGeneratorContext({
    required this.viewer,
    required this.candidate,
    required this.breakdown,
    this.musicSignals = const WhyYouMatchedMusicSignals(),
    this.questionSignals = const WhyYouMatchedQuestionSignals(),
    this.humorAnswerSignals = const WhyYouMatchedHumorAnswerSignals(),
    this.humorCompatibility,
    this.distanceKm,
  });

  final UserProfile viewer;
  final UserProfile candidate;
  final CompatibilityBreakdown breakdown;
  final WhyYouMatchedMusicSignals musicSignals;
  final WhyYouMatchedQuestionSignals questionSignals;
  final WhyYouMatchedHumorAnswerSignals humorAnswerSignals;

  /// From Humor Lab `getMatchHumorCompatibility` — separate from Discover score.
  final HumorCompatibility? humorCompatibility;

  /// Rounded km from server/client distance calc — never raw coordinates.
  final double? distanceKm;

  bool get hasSufficientBreakdown =>
      breakdown.dataQuality != CompatibilityDataQuality.insufficient;
}
