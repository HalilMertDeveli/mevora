import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/music/domain/entities/public_music_profile.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:url_launcher/url_launcher.dart';

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.profileMusicTasteHeading,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (profile.artists.isNotEmpty)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final artist in profile.artists)
                _MusicItemChip(
                  label: artist.name,
                  imageUrl: artist.imageUrl,
                  spotifyUrl: artist.spotifyUrl,
                  rounded: true,
                ),
            ],
          ),
        if (profile.tracks.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final track in profile.tracks)
                _MusicItemChip(
                  label: track.name,
                  sublabel: track.artist.isEmpty ? null : track.artist,
                  imageUrl: track.imageUrl,
                  spotifyUrl: track.spotifyUrl,
                ),
            ],
          ),
        ],
        if (profile.genres.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            profile.genres.map(_titleCase).join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// One artist or track. Tapping opens it in Spotify when a link is present,
/// which is how Spotify expects its content to be attributed and reachable.
class _MusicItemChip extends StatelessWidget {
  const _MusicItemChip({
    required this.label,
    this.sublabel,
    this.imageUrl,
    this.spotifyUrl,
    this.rounded = false,
  });

  final String label;
  final String? sublabel;
  final String? imageUrl;
  final String? spotifyUrl;
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = spotifyUrl;
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imageUrl != null) ...[
            _Thumb(url: imageUrl!, rounded: rounded),
            const SizedBox(width: AppSpacing.xs),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              if (sublabel != null)
                Text(
                  sublabel!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    if (url == null || url.isEmpty) {
      return content;
    }
    return Semantics(
      link: true,
      label: '$label · ${AppLocalizations.of(context).profileMusicOpenInSpotify}',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        onTap: () => _openSpotify(url),
        child: content,
      ),
    );
  }

  Future<void> _openSpotify(String url) async {
    final uri = Uri.tryParse(url);
    // Only ever an open.spotify.com link built server-side from an id, but the
    // scheme is re-checked here so a tampered document cannot launch anything
    // else from a profile card.
    if (uri == null || uri.scheme != 'https' || uri.host != 'open.spotify.com') {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.rounded});

  final String url;
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final provider = MevoraNetworkImages.provider(url);
    if (provider == null) {
      return const SizedBox.shrink();
    }
    const size = 28.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(rounded ? size : AppRadii.sm),
      child: Image(
        image: provider,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox(width: size, height: size),
      ),
    );
  }
}

String _titleCase(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value[0].toUpperCase() + value.substring(1);
}
