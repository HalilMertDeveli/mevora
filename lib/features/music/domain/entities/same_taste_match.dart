import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';

/// Profile that shares listening habits. Not an automatic match.
class SameTasteMatch {
  const SameTasteMatch({
    required this.candidate,
    required this.musicScore,
    this.sharedArtists = const [],
    this.sharedTracks = const [],
    this.sharedGenres = const [],
    this.sharedArtistCount = 0,
    this.sharedTrackCount = 0,
    this.sharedGenreCount = 0,
  });

  final DiscoveryCandidate candidate;
  final int musicScore;
  final List<String> sharedArtists;
  final List<String> sharedTracks;
  final List<String> sharedGenres;
  final int sharedArtistCount;
  final int sharedTrackCount;
  final int sharedGenreCount;
}
