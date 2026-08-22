import 'package:mevora/features/music/domain/entities/music_taste.dart';

enum MusicCompatibilityBand { low, mid, high, veryHigh }

class MusicCompatibilityResult {
  const MusicCompatibilityResult({
    required this.score,
    this.sharedTracks = const [],
    this.sharedArtists = const [],
    this.sharedGenres = const [],
    this.reasons = const [],
  });

  /// 0–100 inclusive. Extra discovery signal — never an automatic match.
  final int score;
  final List<String> sharedTracks;
  final List<String> sharedArtists;
  final List<String> sharedGenres;
  final List<String> reasons;

  MusicCompatibilityBand get band => MusicCompatibilityCalculator.band(score);

  bool get hasSignal => score > 0;
}

/// Shared tracks 40%, artists 30%, genres 20%, recent habits 10%.
abstract final class MusicCompatibilityCalculator {
  static const trackWeight = 0.40;
  static const artistWeight = 0.30;
  static const genreWeight = 0.20;
  static const recentWeight = 0.10;

  /// Ranking-only bonus so music never replaces dating compatibility.
  static const rankingWeight = 0.15;

  static MusicCompatibilityBand band(int score) {
    if (score >= 85) {
      return MusicCompatibilityBand.veryHigh;
    }
    if (score >= 70) {
      return MusicCompatibilityBand.high;
    }
    if (score >= 40) {
      return MusicCompatibilityBand.mid;
    }
    return MusicCompatibilityBand.low;
  }

  static int rankingBonus(int musicScore) {
    if (musicScore <= 0) {
      return 0;
    }
    return (musicScore * rankingWeight).round().clamp(0, 15);
  }

  static MusicCompatibilityResult score({
    required MusicTasteSnapshot viewer,
    required MusicTasteSnapshot candidate,
  }) {
    if (viewer.isEmpty || candidate.isEmpty) {
      return const MusicCompatibilityResult(score: 0);
    }

    final sharedTracks = _intersect(viewer.trackIds, candidate.trackIds);
    final sharedArtists = _intersect(viewer.artistIds, candidate.artistIds);
    final sharedGenres = _intersect(viewer.genres, candidate.genres);
    final recentTracks = _intersect(
      viewer.recentTrackIds,
      candidate.recentTrackIds,
    );
    final recentArtists = _intersect(
      viewer.recentArtistIds,
      candidate.recentArtistIds,
    );

    final tracks = _overlap(viewer.trackIds, candidate.trackIds);
    final artists = _overlap(viewer.artistIds, candidate.artistIds);
    final genres = _overlap(viewer.genres, candidate.genres);
    final recent = _combinedRecentOverlap(
      recentTracks: recentTracks.length,
      recentArtists: recentArtists.length,
      viewerRecent:
          viewer.recentTrackIds.length + viewer.recentArtistIds.length,
      candidateRecent:
          candidate.recentTrackIds.length + candidate.recentArtistIds.length,
    );

    final weighted =
        tracks * trackWeight +
        artists * artistWeight +
        genres * genreWeight +
        recent * recentWeight;
    final reasons = <String>[];
    if (sharedArtists.isNotEmpty) {
      reasons.add('You both listen to ${sharedArtists.take(2).join(', ')}');
    } else if (sharedTracks.isNotEmpty) {
      reasons.add('You share tracks');
    } else if (sharedGenres.isNotEmpty) {
      reasons.add('Similar genres');
    }

    return MusicCompatibilityResult(
      score: (weighted * 100).round().clamp(0, 100),
      sharedTracks: sharedTracks,
      sharedArtists: sharedArtists,
      sharedGenres: sharedGenres,
      reasons: reasons,
    );
  }

  static double _overlap(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) {
      return 0;
    }
    final shared = _intersect(a, b).length;
    final denom = a.length < b.length ? a.length : b.length;
    if (denom == 0) {
      return 0;
    }
    return (shared / denom).clamp(0, 1);
  }

  static double _combinedRecentOverlap({
    required int recentTracks,
    required int recentArtists,
    required int viewerRecent,
    required int candidateRecent,
  }) {
    final denom = viewerRecent < candidateRecent
        ? viewerRecent
        : candidateRecent;
    if (denom <= 0) {
      return 0;
    }
    return ((recentTracks + recentArtists) / denom).clamp(0, 1);
  }

  static List<String> _intersect(List<String> a, List<String> b) {
    final other = b.map(_norm).where((item) => item.isNotEmpty).toSet();
    final seen = <String>{};
    final out = <String>[];
    for (final item in a) {
      final key = _norm(item);
      if (key.isEmpty || !other.contains(key) || !seen.add(key)) {
        continue;
      }
      out.add(item.trim());
    }
    return out;
  }

  static String _norm(String value) => value.trim().toLowerCase();
}
