import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/music_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/music/domain/entities/match_music_compatibility.dart';
import 'package:mevora/features/music/presentation/widgets/music_compatibility_sheet.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';

/// Match-chat music strip. Renders nothing unless both sides have Spotify data.
class MatchMusicCompatibilityBanner extends StatefulWidget {
  const MatchMusicCompatibilityBanner({
    super.key,
    required this.matchId,
    this.analytics,
  });

  final String matchId;
  final AnalyticsProvider? analytics;

  @override
  State<MatchMusicCompatibilityBanner> createState() =>
      _MatchMusicCompatibilityBannerState();
}

class _MatchMusicCompatibilityBannerState
    extends State<MatchMusicCompatibilityBanner> {
  MatchMusicCompatibility? _data;
  var _loading = true;
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    final repo = MusicScope.maybeOf(context);
    if (repo == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _data = MatchMusicCompatibility.unavailable;
        });
      }
      return;
    }
    final result = await repo.getMatchMusicCompatibility(widget.matchId);
    if (!mounted) {
      return;
    }
    final value = result.valueOrNull ?? MatchMusicCompatibility.unavailable;
    setState(() {
      _loading = false;
      _data = value;
    });
    if (value.showDetails || value.showTeaser) {
      unawaited(
        widget.analytics?.logEvent(
          AnalyticsEvents.musicCompatibilityViewed,
          parameters: {
            'premium': value.showDetails,
            'teaser': value.showTeaser,
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (_loading || data == null || !data.available) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (data.showTeaser) {
      return Material(
        color: theme.colorScheme.surfaceContainerHighest,
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.headphones_outlined),
          title: Text(l10n.musicMatchTeaser),
          trailing: Text(
            l10n.musicPremiumUnlock,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          onTap: () => context.push(AppRoutes.boost),
        ),
      );
    }

    if (!data.showDetails) {
      return const SizedBox.shrink();
    }

    final score = data.score!;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () {
          unawaited(
            widget.analytics?.logEvent(AnalyticsEvents.commonTracksViewed),
          );
          unawaited(
            MusicCompatibilitySheet.show(
              context,
              score: score,
              insights: data.insights,
              sharedTracks: data.sharedTracks.map((t) => t.name).toList(),
              sharedArtists: data.sharedArtists.map((a) => a.name).toList(),
              sharedGenres: data.sharedGenres,
              sharedTrackCount: data.sharedTrackCount,
              sharedArtistCount: data.sharedArtistCount,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.musicMatchTitle(score),
                style: theme.textTheme.titleSmall,
              ),
              if (data.sharedTrackCount > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.musicInsightSharedTracks(data.sharedTrackCount),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (data.sharedTracks.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  height: 56,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: data.sharedTracks.length.clamp(0, 5),
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final track = data.sharedTracks[index];
                      final image = MevoraNetworkImages.provider(
                        track.albumImage,
                      );
                      return Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: image == null
                                  ? ColoredBox(
                                      color: theme.colorScheme.primaryContainer,
                                      child: const Icon(Icons.music_note),
                                    )
                                  : Image(image: image, fit: BoxFit.cover),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          SizedBox(
                            width: 120,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  track.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelLarge,
                                ),
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
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
