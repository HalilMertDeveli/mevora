import 'package:mevora/features/music/domain/entities/music_taste.dart';

enum MusicCompatibilityBand { low, mid, high, veryHigh }

enum MusicInsightCode {
  bandVeryHigh,
  bandHigh,
  bandMid,
  bandLow,
  sharedTracks,
  sharedArtists,
  sharedPlaylistTracks,
  sharedRecentTracks,
  topSharedArtist,
  topSharedGenres,
  dataUnavailable,
  notConnected,
}

class MusicInsight {
  const MusicInsight({
    required this.code,
    this.params = const {},
  });

  final MusicInsightCode code;
  final Map<String, Object> params;
}

class MusicCompatibilityBreakdown {
  const MusicCompatibilityBreakdown({
    this.tracks = 0,
    this.artists = 0,
    this.genres = 0,
    this.recent = 0,
    this.playlist = 0,
  });

  final int tracks;
  final int artists;
  final int genres;
  final int recent;
  final int playlist;
}

class MusicCompatibilityResult {
  const MusicCompatibilityResult({
    required this.score,
    this.sharedTracks = const [],
    this.sharedArtists = const [],
    this.sharedGenres = const [],
    this.sharedRecentTracks = const [],
    this.sharedPlaylistTracks = const [],
    this.sharedTrackNames = const [],
    this.sharedArtistNames = const [],
    this.breakdown = const MusicCompatibilityBreakdown(),
    this.insights = const [],
  });

  /// 0–100 inclusive. Extra discovery signal — never an automatic match.
  final int score;
  final List<String> sharedTracks;
  final List<String> sharedArtists;
  final List<String> sharedGenres;
  final List<String> sharedRecentTracks;
  final List<String> sharedPlaylistTracks;
  final List<String> sharedTrackNames;
  final List<String> sharedArtistNames;
  final MusicCompatibilityBreakdown breakdown;
  final List<MusicInsight> insights;

  MusicCompatibilityBand get band => MusicCompatibilityCalculator.band(score);

  bool get hasSignal => score > 0;

  /// Legacy English reasons kept for older callers; prefer [insights] + l10n.
  List<String> get reasons => insights
      .where((item) => item.code == MusicInsightCode.topSharedArtist)
      .map((item) => 'You both listen to ${item.params['name']}')
      .toList();
}

/// Shared tracks / artists / genres / recent / optional playlist overlap.
/// Mirrors `functions/src/musicCompatibility.ts` for client-side previews.
abstract final class MusicCompatibilityCalculator {
  static const trackWeight = 0.40;
  static const artistWeight = 0.30;
  static const genreWeight = 0.20;
  static const recentWeight = 0.10;

  static const trackWeightWithPlaylist = 0.35;
  static const artistWeightWithPlaylist = 0.25;
  static const genreWeightWithPlaylist = 0.20;
  static const playlistWeight = 0.10;
  static const recentWeightWithPlaylist = 0.10;

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
    List<String> trackNames = const [],
    List<String> artistNames = const [],
  }) {
    if (viewer.isEmpty || candidate.isEmpty) {
      return const MusicCompatibilityResult(
        score: 0,
        insights: [MusicInsight(code: MusicInsightCode.dataUnavailable)],
      );
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
    final hasPlaylist =
        viewer.playlistTrackIds.isNotEmpty &&
        candidate.playlistTrackIds.isNotEmpty;
    final sharedPlaylist = hasPlaylist
        ? _intersect(viewer.playlistTrackIds, candidate.playlistTrackIds)
        : const <String>[];

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
    final playlist = hasPlaylist
        ? _overlap(viewer.playlistTrackIds, candidate.playlistTrackIds)
        : 0.0;

    final weighted = hasPlaylist
        ? tracks * trackWeightWithPlaylist +
              artists * artistWeightWithPlaylist +
              genres * genreWeightWithPlaylist +
              playlist * playlistWeight +
              recent * recentWeightWithPlaylist
        : tracks * trackWeight +
              artists * artistWeight +
              genres * genreWeight +
              recent * recentWeight;

    final scoreValue = (weighted * 100).round().clamp(0, 100);
    final resolvedTrackNames = trackNames.isNotEmpty
        ? trackNames
        : sharedTracks;
    final resolvedArtistNames = artistNames.isNotEmpty
        ? artistNames
        : sharedArtists;

    return MusicCompatibilityResult(
      score: scoreValue,
      sharedTracks: sharedTracks,
      sharedArtists: sharedArtists,
      sharedGenres: sharedGenres,
      sharedRecentTracks: recentTracks,
      sharedPlaylistTracks: sharedPlaylist,
      sharedTrackNames: resolvedTrackNames,
      sharedArtistNames: resolvedArtistNames,
      breakdown: MusicCompatibilityBreakdown(
        tracks: (tracks * 100).round(),
        artists: (artists * 100).round(),
        genres: (genres * 100).round(),
        recent: (recent * 100).round(),
        playlist: (playlist * 100).round(),
      ),
      insights: buildInsights(
        score: scoreValue,
        sharedTrackCount: sharedTracks.length,
        sharedArtistCount: sharedArtists.length,
        sharedGenreNames: sharedGenres,
        sharedRecentTrackCount: recentTracks.length,
        sharedPlaylistTrackCount: sharedPlaylist.length,
        topArtistName: resolvedArtistNames.isEmpty
            ? null
            : resolvedArtistNames.first,
      ),
    );
  }

  static List<MusicInsight> buildInsights({
    required int score,
    required int sharedTrackCount,
    required int sharedArtistCount,
    required List<String> sharedGenreNames,
    required int sharedRecentTrackCount,
    required int sharedPlaylistTrackCount,
    String? topArtistName,
  }) {
    final insights = <MusicInsight>[
      MusicInsight(code: _bandCode(score)),
    ];
    if (sharedTrackCount > 0) {
      insights.add(
        MusicInsight(
          code: MusicInsightCode.sharedTracks,
          params: {'count': sharedTrackCount},
        ),
      );
    }
    if (sharedArtistCount > 0) {
      insights.add(
        MusicInsight(
          code: MusicInsightCode.sharedArtists,
          params: {'count': sharedArtistCount},
        ),
      );
    }
    if (sharedPlaylistTrackCount > 0) {
      insights.add(
        MusicInsight(
          code: MusicInsightCode.sharedPlaylistTracks,
          params: {'count': sharedPlaylistTrackCount},
        ),
      );
    }
    if (sharedRecentTrackCount > 0) {
      insights.add(
        MusicInsight(
          code: MusicInsightCode.sharedRecentTracks,
          params: {'count': sharedRecentTrackCount},
        ),
      );
    }
    if (topArtistName != null && topArtistName.isNotEmpty) {
      insights.add(
        MusicInsight(
          code: MusicInsightCode.topSharedArtist,
          params: {'name': topArtistName},
        ),
      );
    }
    if (sharedGenreNames.isNotEmpty) {
      insights.add(
        MusicInsight(
          code: MusicInsightCode.topSharedGenres,
          params: {'genres': sharedGenreNames.take(2).join(', ')},
        ),
      );
    }
    if (sharedTrackCount == 0 &&
        sharedArtistCount == 0 &&
        sharedGenreNames.isEmpty &&
        sharedPlaylistTrackCount == 0 &&
        sharedRecentTrackCount == 0) {
      insights.add(
        const MusicInsight(code: MusicInsightCode.dataUnavailable),
      );
    }
    return insights;
  }

  static MusicInsightCode parseInsightCode(String? raw) {
    return switch (raw) {
      'band_very_high' => MusicInsightCode.bandVeryHigh,
      'band_high' => MusicInsightCode.bandHigh,
      'band_mid' => MusicInsightCode.bandMid,
      'band_low' => MusicInsightCode.bandLow,
      'shared_tracks' => MusicInsightCode.sharedTracks,
      'shared_artists' => MusicInsightCode.sharedArtists,
      'shared_playlist_tracks' => MusicInsightCode.sharedPlaylistTracks,
      'shared_recent_tracks' => MusicInsightCode.sharedRecentTracks,
      'top_shared_artist' => MusicInsightCode.topSharedArtist,
      'top_shared_genres' => MusicInsightCode.topSharedGenres,
      'not_connected' => MusicInsightCode.notConnected,
      _ => MusicInsightCode.dataUnavailable,
    };
  }

  static MusicInsightCode _bandCode(int score) {
    final band = MusicCompatibilityCalculator.band(score);
    return switch (band) {
      MusicCompatibilityBand.veryHigh => MusicInsightCode.bandVeryHigh,
      MusicCompatibilityBand.high => MusicInsightCode.bandHigh,
      MusicCompatibilityBand.mid => MusicInsightCode.bandMid,
      MusicCompatibilityBand.low => MusicInsightCode.bandLow,
    };
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
