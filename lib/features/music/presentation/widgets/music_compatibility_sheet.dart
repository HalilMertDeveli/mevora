import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/music/domain/services/music_compatibility.dart';
import 'package:mevora/features/music/domain/services/music_insight_localizer.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

/// Explains music compatibility with localized insights and shared lists.
class MusicCompatibilitySheet extends StatelessWidget {
  const MusicCompatibilitySheet({
    super.key,
    required this.score,
    this.insights = const [],
    this.sharedTracks = const [],
    this.sharedArtists = const [],
    this.sharedGenres = const [],
    this.sharedTrackCount,
    this.sharedArtistCount,
    this.sharedPlaylistTrackCount,
    this.maxVisibleTracks = 6,
    this.maxVisibleArtists = 5,
  });

  final int score;
  final List<MusicInsight> insights;
  final List<String> sharedTracks;
  final List<String> sharedArtists;
  final List<String> sharedGenres;
  final int? sharedTrackCount;
  final int? sharedArtistCount;
  final int? sharedPlaylistTrackCount;
  final int maxVisibleTracks;
  final int maxVisibleArtists;

  static Future<void> show(
    BuildContext context, {
    required int score,
    List<MusicInsight> insights = const [],
    List<String> sharedTracks = const [],
    List<String> sharedArtists = const [],
    List<String> sharedGenres = const [],
    int? sharedTrackCount,
    int? sharedArtistCount,
    int? sharedPlaylistTrackCount,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => MusicCompatibilitySheet(
        score: score,
        insights: insights,
        sharedTracks: sharedTracks,
        sharedArtists: sharedArtists,
        sharedGenres: sharedGenres,
        sharedTrackCount: sharedTrackCount,
        sharedArtistCount: sharedArtistCount,
        sharedPlaylistTrackCount: sharedPlaylistTrackCount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bullets = MusicInsightLocalizer.bulletLines(l10n, insights);
    final trackTotal = sharedTrackCount ?? sharedTracks.length;
    final artistTotal = sharedArtistCount ?? sharedArtists.length;
    final visibleTracks = sharedTracks.take(maxVisibleTracks).toList();
    final visibleArtists = sharedArtists.take(maxVisibleArtists).toList();
    final remainingTracks = trackTotal - visibleTracks.length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                MusicInsightLocalizer.title(l10n, score),
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                MusicInsightLocalizer.headline(l10n, score),
                style: theme.textTheme.bodyLarge,
              ),
              if (bullets.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                ...bullets.map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Text('• $line'),
                  ),
                ),
              ],
              if (visibleArtists.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.musicSharedArtistsHeading,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: visibleArtists
                      .map((name) => MevoraChip(label: name, compact: true))
                      .toList(),
                ),
                if (artistTotal > visibleArtists.length)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      l10n.musicViewAllShared(artistTotal),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
              if (visibleTracks.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.musicSharedTracksHeading,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                ...visibleTracks.map(
                  (name) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Text('🎵 $name'),
                  ),
                ),
                if (remainingTracks > 0)
                  Text(
                    l10n.musicViewAllShared(trackTotal),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
              if (sharedGenres.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.musicSharedGenresHeading,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: sharedGenres
                      .map((name) => MevoraChip(label: name, compact: true))
                      .toList(),
                ),
              ],
              if (sharedPlaylistTrackCount != null &&
                  sharedPlaylistTrackCount! > 0) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.musicInsightSharedPlaylistTracks(
                    sharedPlaylistTrackCount!,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
