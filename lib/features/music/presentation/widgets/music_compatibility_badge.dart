import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/features/music/domain/services/music_compatibility.dart';
import 'package:mevora/features/music/presentation/widgets/music_compatibility_sheet.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

class MusicCompatibilityBadge extends StatelessWidget {
  const MusicCompatibilityBadge({
    super.key,
    required this.score,
    this.compact = true,
    this.sharedTracks = const [],
    this.sharedArtists = const [],
    this.sharedGenres = const [],
    this.insights = const [],
    this.sharedTrackCount,
    this.sharedArtistCount,
    this.sharedPlaylistTrackCount,
    this.onTap,
  });

  final int score;
  final bool compact;
  final List<String> sharedTracks;
  final List<String> sharedArtists;
  final List<String> sharedGenres;
  final List<MusicInsight> insights;
  final int? sharedTrackCount;
  final int? sharedArtistCount;
  final int? sharedPlaylistTrackCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: onTap ??
          () {
            unawaited(
              MusicCompatibilitySheet.show(
                context,
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
          },
      child: MevoraChip(
        label: compact
            ? l10n.musicCompatibilityShort(score)
            : l10n.musicCompatibilityPercent(score),
        selected: MusicCompatibilityCalculator.band(score) !=
            MusicCompatibilityBand.low,
        compact: compact,
      ),
    );
  }
}
