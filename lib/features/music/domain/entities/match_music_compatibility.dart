import 'package:mevora/features/music/domain/entities/music_track.dart';
import 'package:mevora/features/music/domain/entities/normalized_music_profile.dart';
import 'package:mevora/features/music/domain/services/music_compatibility.dart';

/// Match-screen music compatibility payload from `getMatchMusicCompatibility`.
///
/// Never invents data: [available] is false when either side lacks Spotify taste
/// or the users are not in an active match.
class MatchMusicCompatibility {
  const MatchMusicCompatibility({
    required this.available,
    this.premiumRequired = false,
    this.teaser = false,
    this.score,
    this.overallCompatibilityScore,
    this.sharedTrackCount = 0,
    this.sharedArtistCount = 0,
    this.sharedRecentTrackCount = 0,
    this.sharedTracks = const [],
    this.sharedArtists = const [],
    this.sharedGenres = const [],
    this.insights = const [],
    this.viewerRecentArtists = const [],
    this.peerRecentArtists = const [],
    this.reason,
  });

  static const unavailable = MatchMusicCompatibility(available: false);

  final bool available;
  final bool premiumRequired;
  final bool teaser;
  final int? score;
  final int? overallCompatibilityScore;
  final int sharedTrackCount;
  final int sharedArtistCount;
  final int sharedRecentTrackCount;
  final List<MusicTrack> sharedTracks;
  final List<MusicArtist> sharedArtists;
  final List<String> sharedGenres;
  final List<MusicInsight> insights;
  final List<RecentArtist> viewerRecentArtists;
  final List<RecentArtist> peerRecentArtists;
  final String? reason;

  bool get showTeaser => available && teaser && premiumRequired;
  bool get showDetails => available && !premiumRequired && score != null;
}
