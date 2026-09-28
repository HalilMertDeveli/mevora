import 'package:mevora/features/music/domain/services/music_compatibility.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Maps machine insight codes to localized copy (TR/EN via ARB).
abstract final class MusicInsightLocalizer {
  static String headline(AppLocalizations l10n, int score) {
    return switch (MusicCompatibilityCalculator.band(score)) {
      MusicCompatibilityBand.veryHigh ||
      MusicCompatibilityBand.high =>
        l10n.musicInsightBandHigh,
      MusicCompatibilityBand.mid => l10n.musicInsightBandMid,
      MusicCompatibilityBand.low => l10n.musicInsightBandLow,
    };
  }

  static String title(AppLocalizations l10n, int score) {
    return l10n.musicMatchTitle(score);
  }

  static String line(AppLocalizations l10n, MusicInsight insight) {
    final count = _int(insight.params['count']);
    final name = insight.params['name']?.toString() ?? '';
    final genres = insight.params['genres']?.toString() ?? '';
    return switch (insight.code) {
      MusicInsightCode.bandVeryHigh || MusicInsightCode.bandHigh =>
        l10n.musicInsightBandHigh,
      MusicInsightCode.bandMid => l10n.musicInsightBandMid,
      MusicInsightCode.bandLow => l10n.musicInsightBandLow,
      MusicInsightCode.sharedTracks => l10n.musicInsightSharedTracks(count),
      MusicInsightCode.sharedArtists => l10n.musicInsightSharedArtists(count),
      MusicInsightCode.sharedPlaylistTracks =>
        l10n.musicInsightSharedPlaylistTracks(count),
      MusicInsightCode.sharedRecentTracks =>
        l10n.musicInsightSharedRecentTracks(count),
      MusicInsightCode.topSharedArtist =>
        l10n.musicInsightTopSharedArtist(name),
      MusicInsightCode.topSharedGenres =>
        l10n.musicInsightTopSharedGenres(genres),
      MusicInsightCode.notConnected => l10n.musicSpotifyNotConnected,
      MusicInsightCode.dataUnavailable => l10n.musicInsightDataUnavailable,
    };
  }

  static List<String> bulletLines(
    AppLocalizations l10n,
    List<MusicInsight> insights,
  ) {
    final out = <String>[];
    for (final insight in insights) {
      if (insight.code == MusicInsightCode.bandVeryHigh ||
          insight.code == MusicInsightCode.bandHigh ||
          insight.code == MusicInsightCode.bandMid ||
          insight.code == MusicInsightCode.bandLow) {
        continue;
      }
      if (insight.code == MusicInsightCode.dataUnavailable && out.isNotEmpty) {
        continue;
      }
      out.add(line(l10n, insight));
    }
    return out;
  }

  static int _int(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
