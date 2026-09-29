import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:url_launcher/url_launcher.dart';

/// Mevora's music vocabulary. Artwork gives each module its personality;
/// Mevora owns everything around it (dusk tone, serif headings, the
/// overlapping-circle motif) so it never reads as a Spotify screen.

/// Album or playlist art, square with a small radius.
class MusicCover extends StatelessWidget {
  const MusicCover({super.key, this.url, this.size = 48, this.circle = false});

  final String? url;
  final double size;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final provider = (url == null || url!.isEmpty)
        ? null
        : MevoraNetworkImages.provider(url);
    final fallback = ColoredBox(
      color: p.musicContainer,
      child: Center(
        child: Icon(
          circle ? MevoraIcons.headphones : MevoraIcons.album,
          size: size * 0.42,
          color: p.music,
        ),
      ),
    );
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(circle ? size : AppRadii.sm),
      child: SizedBox.square(
        dimension: size,
        child: provider == null
            ? fallback
            : Image(
                image: ResizeImage(
                  provider,
                  width: (size * dpr).round(),
                  policy: ResizeImagePolicy.fit,
                ),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                // Show the placeholder until the first frame arrives, so a
                // slow or unreachable cover never leaves an empty hole.
                frameBuilder: (context, child, frame, sync) =>
                    sync || frame != null ? child : fallback,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

/// Opens an open.spotify.com link — only that host, only https. Spotify
/// content stays attributed and reachable, which its terms expect.
Future<void> openSpotifyLink(String? url) async {
  if (url == null || url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host != 'open.spotify.com') {
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// A round artist portrait with the name beneath.
class MusicArtistTile extends StatelessWidget {
  const MusicArtistTile({
    super.key,
    required this.name,
    this.imageUrl,
    this.spotifyUrl,
    this.size = 68,
  });

  final String name;
  final String? imageUrl;
  final String? spotifyUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tile = SizedBox(
      width: size + AppSpacing.md,
      child: Column(
        children: [
          MusicCover(url: imageUrl, size: size, circle: true),
          const SizedBox(height: AppSpacing.sm),
          Text(
            name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: context.palette.textPrimary,
              height: 16 / 13,
            ),
          ),
        ],
      ),
    );
    if (spotifyUrl == null || spotifyUrl!.isEmpty) {
      return Semantics(
        label: name,
        child: ExcludeSemantics(child: tile),
      );
    }
    return Semantics(
      link: true,
      label: '$name · ${l10n.profileMusicOpenInSpotify}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: () => openSpotifyLink(spotifyUrl),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: tile,
        ),
      ),
    );
  }
}

/// A horizontally scrolling row of artists, bleeding to the page edge.
class MusicArtistRow extends StatelessWidget {
  const MusicArtistRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 124,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

/// A track: cover, title, artist; optional rank and Spotify link.
class MusicTrackRow extends StatelessWidget {
  const MusicTrackRow({
    super.key,
    required this.title,
    this.artist,
    this.imageUrl,
    this.spotifyUrl,
    this.rank,
    this.trailing,
    this.icon,
  });

  final String title;
  final String? artist;
  final String? imageUrl;
  final String? spotifyUrl;
  final int? rank;
  final Widget? trailing;

  /// Replaces the cover with a glyph (playlists without art).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final l10n = AppLocalizations.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          if (rank != null)
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: p.textTertiary,
                ),
              ),
            ),
          if (icon != null)
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: p.musicContainer,
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: Icon(icon, color: p.music, size: 22),
            )
          else
            MusicCover(url: imageUrl),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                if (artist != null && artist!.isNotEmpty)
                  Text(
                    artist!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                  ),
              ],
            ),
          ),
          ?trailing,
          if (spotifyUrl != null && spotifyUrl!.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            Icon(MevoraIcons.externalLink, size: 16, color: p.textTertiary),
          ],
        ],
      ),
    );
    if (spotifyUrl == null || spotifyUrl!.isEmpty) return row;
    return Semantics(
      link: true,
      label: '$title · ${artist ?? ''} · ${l10n.profileMusicOpenInSpotify}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: () => openSpotifyLink(spotifyUrl),
        child: row,
      ),
    );
  }
}

/// Up to three artist portraits overlapping like the Mevora mark.
class MusicPortraitStack extends StatelessWidget {
  const MusicPortraitStack({
    super.key,
    required this.imageUrls,
    this.size = 56,
  });

  final List<String?> imageUrls;
  final double size;

  @override
  Widget build(BuildContext context) {
    final urls = imageUrls.take(3).toList();
    if (urls.isEmpty) return const SizedBox.shrink();
    final step = size * 0.62;
    return SizedBox(
      width: size + step * (urls.length - 1),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < urls.length; i++)
            Positioned(
              left: step * i,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.duskInk, width: 2.5),
                ),
                child: MusicCover(url: urls[i], size: size - 5, circle: true),
              ),
            ),
        ],
      ),
    );
  }
}

typedef GenreSlice = ({String name, int percent});

/// Genre composition as one stacked bar with a legend — the shape of a
/// taste at a glance, rather than a list of disconnected bars.
class GenreComposition extends StatelessWidget {
  const GenreComposition({
    super.key,
    required this.genres,
    this.onDark = false,
  });

  final List<GenreSlice> genres;
  final bool onDark;

  static const _shades = [
    AppColors.dusk,
    Color(0xFF8577C7),
    Color(0xFFB2A8E0),
    AppColors.marigold,
    AppColors.sage,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slices = genres.where((g) => g.percent > 0).take(5).toList();
    if (slices.isEmpty) return const SizedBox.shrink();
    final text = onDark ? AppColors.onMedia : context.palette.textPrimary;
    final muted = onDark
        ? AppColors.onMediaMuted
        : context.palette.textSecondary;
    return Semantics(
      label: slices.map((g) => '${g.name} ${g.percent}%').join(', '),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: SizedBox(
              height: 10,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < slices.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: slices[i].percent.clamp(1, 100),
                      child: ColoredBox(color: _shades[i % _shades.length]),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              for (var i = 0; i < slices.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _shades[i % _shades.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs + 2),
                    Text(
                      _titleCase(slices[i].name),
                      style: theme.textTheme.labelMedium?.copyWith(color: text),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '${slices[i].percent}%',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Data from Spotify" line — attribution for Spotify-sourced content.
class SpotifyAttribution extends StatelessWidget {
  const SpotifyAttribution({super.key, this.onDark = false});

  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final color = onDark
        ? AppColors.onMediaMuted
        : context.palette.textTertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(MevoraIcons.spotify, size: 14, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(
          'Spotify',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

String _titleCase(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
