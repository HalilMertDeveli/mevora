import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/music/domain/entities/public_music_profile.dart';
import 'package:mevora/features/music/presentation/widgets/music_ui.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_section_header.dart';

/// The Music Taste block on a dating profile.
///
/// Renders only what its owner explicitly published — at most three artists,
/// three tracks and a short genre line. It is given a [PublicMusicProfile],
/// never a music summary, so there is no path by which private listening data
/// could reach this widget.
class PublicMusicTasteSection extends StatelessWidget {
  const PublicMusicTasteSection({super.key, required this.profile});

  final PublicMusicProfile profile;

  @override
  Widget build(BuildContext context) {
    // Nothing published, or hidden by its owner: draw nothing at all rather
    // than an empty Spotify card.
    if (!profile.hasContent) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = context.palette;
    final summary = _generalTaste(l10n, profile.taste);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MevoraSectionHeader(
          title: l10n.profileMusicTasteHeading,
          icon: MevoraIcons.musicActive,
          iconColor: p.music,
        ),
        const SizedBox(height: AppSpacing.s12),
        MevoraCard(
          color: p.musicContainer.withValues(alpha: 0.55),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.s12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The general summary already names the genres, so the bare
              // genre line is only the fallback for a card published before
              // the analysis existed.
              if (summary.isNotEmpty) ...[
                Text(
                  l10n.musicTasteGeneralHeading,
                  style: theme.textTheme.labelMedium?.copyWith(color: p.music),
                ),
                const SizedBox(height: AppSpacing.xs),
                for (final line in summary.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Text(
                      line,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: p.onMusicContainer,
                        fontSize: 15,
                        height: 22 / 15,
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
              ] else if (profile.genres.isNotEmpty) ...[
                Text(
                  profile.genres.map(_titleCase).join(' · '),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: p.onMusicContainer,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: AppSpacing.s12),
              ],
              if (profile.artists.isNotEmpty)
                MusicArtistRow(
                  children: [
                    for (final artist in profile.artists)
                      MusicArtistTile(
                        name: artist.name,
                        imageUrl: artist.imageUrl,
                        spotifyUrl: artist.spotifyUrl,
                      ),
                  ],
                ),
              for (final track in profile.tracks)
                MusicTrackRow(
                  title: track.name,
                  artist: track.artist,
                  imageUrl: track.imageUrl,
                  spotifyUrl: track.spotifyUrl,
                ),
              const SizedBox(height: AppSpacing.xs),
              const Align(
                alignment: Alignment.centerRight,
                child: SpotifyAttribution(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// At most three plain statements about what this member generally listens
  /// to. Each is a fact the backend derived and can be checked against the
  /// data — never a claim about the person.
  List<String> _generalTaste(AppLocalizations l10n, PublicMusicTaste taste) {
    if (!taste.hasContent) return const [];
    final lines = <String>[];
    final dominant = taste.dominantGenre;
    if (dominant != null && dominant.isNotEmpty) {
      final named = [dominant, ...taste.secondaryGenres].map(_titleCase);
      lines.add(l10n.musicTasteDominant(named.join(', ')));
    }
    if (taste.signatureArtists.isNotEmpty) {
      lines.add(l10n.musicTasteSignature(taste.signatureArtists.join(', ')));
    }
    // Only worth saying when more than one artist has actually stayed.
    if (lines.length < 3 && taste.stableArtistCount >= 2) {
      lines.add(l10n.musicTasteStable(taste.stableArtistCount));
    }
    return lines;
  }
}

String _titleCase(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value[0].toUpperCase() + value.substring(1);
}
