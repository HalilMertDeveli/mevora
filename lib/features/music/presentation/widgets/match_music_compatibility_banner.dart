import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/di/music_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/music/domain/entities/match_music_compatibility.dart';
import 'package:mevora/features/music/presentation/widgets/music_compatibility_sheet.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/features/music/presentation/widgets/music_ui.dart';
import 'package:mevora/shared/widgets/mevora_context_row.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

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

    if (data.showTeaser) {
      return MevoraContextRow(
        icon: MevoraIcons.track,
        tone: MevoraTone.music,
        title: l10n.musicMatchTeaser,
        trailing: MevoraPill(
          label: l10n.musicPremiumUnlock,
          icon: MevoraIcons.premium,
          tone: MevoraTone.premium,
          dense: true,
        ),
        onTap: () => context.push(AppRoutes.premium),
      );
    }

    if (!data.showDetails) {
      return const SizedBox.shrink();
    }

    final score = data.score!;
    return MevoraContextRow(
      icon: MevoraIcons.track,
      tone: MevoraTone.music,
      title: l10n.musicMatchTitle(score),
      subtitle: data.sharedTrackCount > 0
          ? l10n.musicInsightSharedTracks(data.sharedTrackCount)
          : null,
      trailing: data.sharedTracks.isEmpty
          ? null
          : MusicPortraitStack(
              size: 30,
              imageUrls: [for (final t in data.sharedTracks) t.albumImage],
            ),
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
    );
  }
}
