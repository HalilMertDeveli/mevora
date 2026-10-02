import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/app_operations_scope.dart';
import 'package:mevora/core/di/music_scope.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/app_operations/domain/app_operations_config.dart';
import 'package:mevora/features/discovery/presentation/pages/discovery_profile_details_page.dart';
import 'package:mevora/features/music/domain/entities/music_track.dart';
import 'package:mevora/features/music/domain/entities/same_taste_match.dart';
import 'package:mevora/features/music/presentation/controllers/music_controller.dart';
import 'package:mevora/features/music/presentation/widgets/music_compatibility_badge.dart';
import 'package:mevora/features/music/presentation/widgets/music_ui.dart';
import 'package:mevora/features/music/presentation/widgets/public_music_visibility_card.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_page_transitions.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';
import 'package:mevora/shared/widgets/mevora_banner.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_dialog.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_list.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';
import 'package:mevora/shared/widgets/mevora_section_header.dart';

class MusicPage extends StatefulWidget {
  const MusicPage({super.key, this.controller});

  final MusicController? controller;

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  MusicController? _owned;
  MusicController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) {
      return;
    }
    final provided = widget.controller;
    if (provided != null) {
      _controller = provided;
      unawaited(provided.load());
      return;
    }
    final repository = MusicScope.maybeOf(context);
    if (repository == null) {
      return;
    }
    _owned = MusicController(repository: repository);
    _controller = _owned;
    unawaited(_owned!.load());
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    if (controller == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.musicTitle)),
        body: MevoraEmptyState(
          art: MevoraArt.music,
          title: l10n.musicTitle,
          message: l10n.musicUnconnectedCopy,
        ),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        return Scaffold(
          appBar: AppBar(title: Text(l10n.musicTitle)),
          body: SafeArea(
            child: state.isLoading
                ? MevoraLoading.page(
                    message: l10n.loading,
                    art: MevoraArt.music,
                  )
                : state.loadFailed
                ? _MusicLoadFailedView(controller: controller)
                : state.connected
                ? _ConnectedMusicView(controller: controller)
                : _UnconnectedMusicView(controller: controller),
          ),
        );
      },
    );
  }
}

class _UnconnectedMusicView extends StatelessWidget {
  const _UnconnectedMusicView({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final connecting = controller.state.phase == MusicConnectPhase.connecting;
    final error = _musicError(l10n, controller.state.failure);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.lg,
        AppSpacing.screenPadding,
        AppSpacing.xl,
      ),
      children: [
        Center(
          child: MevoraSpot(art: MevoraArt.music, animate: connecting),
        ),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(
            l10n.musicUnconnectedHeadline,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        Text(
          l10n.musicUnconnectedCopy,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: context.palette.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        MevoraBanner(
          message: l10n.musicPrivacyNotice,
          icon: MevoraIcons.lock,
          tone: MevoraTone.music,
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.s12),
          MevoraBanner(message: error, tone: MevoraTone.error),
        ],
        const SizedBox(height: AppSpacing.xl),
        if (AppOperationsScope.isFeatureEnabled(context, AppFeature.spotify))
          MevoraButton(
            label: l10n.musicConnectCta,
            icon: MevoraIcons.spotify,
            size: MevoraButtonSize.large,
            isLoading: connecting,
            onPressed: connecting ? null : controller.connectSpotify,
          )
        else
          MevoraBanner(
            key: const Key('spotifyUnavailable'),
            message: l10n.appOpsSpotifyUnavailable,
            tone: MevoraTone.warning,
          ),
      ],
    );
  }
}

class _ConnectedMusicView extends StatelessWidget {
  const _ConnectedMusicView({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = controller.state;
    final profile = state.profile;
    final repository = MusicScope.maybeOf(context);
    final syncing = state.phase == MusicConnectPhase.syncing;
    final error = _musicError(l10n, state.failure);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.sm,
        AppSpacing.screenPadding,
        AppSpacing.xl,
      ),
      children: [
        _MusicSignatureCard(
          title: l10n.musicProfileTitle,
          genres: [
            for (final g in profile.genres) (name: g.name, percent: g.percent),
          ],
          artistImages: [for (final a in profile.profileTopArtists) a.image],
          syncing: syncing,
          syncingLabel: l10n.musicSyncing,
          emptyLabel: l10n.musicSameTasteEmpty,
          connectedLabel: l10n.musicConnected,
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.md),
          MevoraBanner(message: error, tone: MevoraTone.error),
        ],
        if (profile.hasLimitedData) ...[
          const SizedBox(height: AppSpacing.md),
          MevoraBanner(message: l10n.musicLimitedData, tone: MevoraTone.info),
        ],
        // Connection and visibility are separate: this card publishes or
        // hides the selection without touching the Spotify connection.
        if (repository != null) ...[
          const SizedBox(height: AppSpacing.lg),
          PublicMusicVisibilityCard(
            repository: repository,
            profile: profile,
            onChanged: () => unawaited(controller.load()),
          ),
        ],
        // The four collections the Music Profile is built from. Each is
        // already capped by the backend; the screen only lays them out.
        ..._artistSection(
          context,
          title: l10n.musicTopArtistsTitle,
          artists: profile.profileTopArtists,
        ),
        ..._artistSection(
          context,
          title: l10n.musicFollowedArtistsTitle,
          artists: profile.followedArtists,
          // An older connection has no permission to read follows. Say so
          // and offer the way out, rather than an empty list that reads as
          // "you follow nobody".
          note: profile.canReconnectForFollowedArtists
              ? l10n.musicFollowedArtistsReconnect
              : null,
        ),
        ..._trackSection(
          context,
          title: l10n.musicTopTracksTitle,
          tracks: profile.profileTopTracks,
        ),
        ..._playlistSection(context, playlists: profile.playlists),
        const SizedBox(height: AppSpacing.xl),
        MevoraSectionHeader(
          title: l10n.musicSameTasteTitle,
          icon: MevoraIcons.people,
          iconColor: context.palette.music,
        ),
        const SizedBox(height: AppSpacing.s12),
        if (state.sameTaste.isEmpty)
          MevoraCard(
            emphasis: MevoraCardEmphasis.quiet,
            child: MevoraEmptyState(
              art: MevoraArt.music,
              compact: true,
              title: l10n.musicSameTasteTitle,
              message: l10n.musicSameTasteEmpty,
            ),
          )
        else
          for (final match in state.sameTaste)
            _SameTasteTile(
              match: match,
              onTap: () {
                unawaited(
                  Navigator.of(context).push(
                    MevoraPageTransitions.route<void>(
                      builder: (_) => DiscoveryProfileDetailsPage(
                        candidate: match.candidate,
                      ),
                    ),
                  ),
                );
              },
            ),
        // "This week's music" used to close this page. It is a community chart
        // of the last seven days, and putting it here let a passing week read
        // as the member's musical identity. What represents them is the
        // published Music Taste and the general summary above it. The weekly
        // aggregate stays in the backend for whatever wants a chart, rather
        // than on the page that describes a person.
        const SizedBox(height: AppSpacing.xl),
        MevoraListGroup(
          children: [
            MevoraListRow(
              title: 'Spotify',
              subtitle: profile.displayName,
              leading: const MevoraIconBadge(
                icon: MevoraIcons.spotify,
                tone: MevoraTone.music,
                size: 36,
              ),
              showChevron: false,
            ),
            MevoraListRow(
              title: l10n.musicRefresh,
              subtitle: state.canRefresh ? null : l10n.musicRefreshCooldown,
              icon: MevoraIcons.refresh,
              enabled: state.canRefresh && !syncing,
              trailing: syncing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              showChevron: false,
              onTap: state.canRefresh && !syncing ? controller.syncTaste : null,
            ),
            MevoraListRow(
              title: l10n.musicDisconnectCta,
              icon: MevoraIcons.signOut,
              destructive: true,
              showChevron: false,
              enabled: !syncing,
              onTap: syncing
                  ? null
                  : () => unawaited(_confirmDisconnect(context, controller)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(l10n.musicPrivacyNotice, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// The member's musical signature: their top artists overlapping like the
/// Mevora mark, and the shape of their taste as one composition bar.
class _MusicSignatureCard extends StatelessWidget {
  const _MusicSignatureCard({
    required this.title,
    required this.genres,
    required this.artistImages,
    required this.syncing,
    required this.syncingLabel,
    required this.emptyLabel,
    required this.connectedLabel,
  });

  final String title;
  final List<GenreSlice> genres;
  final List<String?> artistImages;
  final bool syncing;
  final String syncingLabel;
  final String emptyLabel;

  /// "Spotify connected" — the connection state and the attribution in one.
  final String connectedLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topGenres = genres.take(3).map((g) => _titleCase(g.name)).join(' · ');
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s20),
      decoration: BoxDecoration(
        color: AppColors.duskInk,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (artistImages.isNotEmpty) ...[
                MusicPortraitStack(imageUrls: artistImages),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: AppColors.onMedia,
                        ),
                      ),
                    ),
                    if (topGenres.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        topGenres,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.onMediaMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s20),
          if (syncing)
            Row(
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.onMedia,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  syncingLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.onMediaMuted,
                  ),
                ),
              ],
            )
          else if (genres.isEmpty)
            Text(
              emptyLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onMediaMuted,
              ),
            )
          else
            GenreComposition(genres: genres, onDark: true),
          const SizedBox(height: AppSpacing.md),
          MevoraPill(
            label: connectedLabel,
            icon: MevoraIcons.spotify,
            tone: MevoraTone.onMedia,
            dense: true,
          ),
        ],
      ),
    );
  }
}

/// One titled row of artists, or nothing when there is nothing to show.
///
/// A note replaces the list when Mevora cannot read the data yet — an empty
/// section would otherwise claim the member follows nobody.
List<Widget> _artistSection(
  BuildContext context, {
  required String title,
  required List<MusicArtist> artists,
  String? note,
}) {
  final theme = Theme.of(context);
  if (artists.isEmpty && note == null) {
    return const [];
  }
  return [
    const SizedBox(height: AppSpacing.xl),
    MevoraSectionHeader(title: title),
    const SizedBox(height: AppSpacing.s12),
    if (artists.isNotEmpty)
      MusicArtistRow(
        children: [
          for (final artist in artists)
            MusicArtistTile(name: artist.name, imageUrl: artist.image),
        ],
      ),
    if (note != null) ...[
      const SizedBox(height: AppSpacing.xs),
      Text(note, style: theme.textTheme.bodyMedium),
    ],
  ];
}

/// Top tracks, ranked.
List<Widget> _trackSection(
  BuildContext context, {
  required String title,
  required List<MusicTrack> tracks,
}) {
  if (tracks.isEmpty) {
    return const [];
  }
  return [
    const SizedBox(height: AppSpacing.xl),
    MevoraSectionHeader(title: title),
    const SizedBox(height: AppSpacing.xs),
    for (var i = 0; i < tracks.length; i++)
      MusicTrackRow(
        rank: i + 1,
        title: tracks[i].name,
        artist: tracks[i].artist,
        imageUrl: tracks[i].albumImage,
      ),
  ];
}

/// The member's own playlists. Names stay on this screen: they are the
/// owner's, and nothing here reaches another member's profile.
List<Widget> _playlistSection(
  BuildContext context, {
  required List<MusicPlaylist> playlists,
}) {
  final l10n = AppLocalizations.of(context);
  if (playlists.isEmpty) {
    return const [];
  }
  return [
    const SizedBox(height: AppSpacing.xl),
    MevoraSectionHeader(title: l10n.musicPlaylistsTitle),
    const SizedBox(height: AppSpacing.xs),
    for (final playlist in playlists)
      MusicTrackRow(
        icon: MevoraIcons.playlist,
        title: playlist.name,
        artist: playlist.trackCount > 0
            ? l10n.musicPlaylistTrackCount(playlist.trackCount)
            : null,
      ),
  ];
}

class _SameTasteTile extends StatelessWidget {
  const _SameTasteTile({required this.match, required this.onTap});

  final SameTasteMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final candidate = match.candidate;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: MevoraCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.s12 + 2),
        child: Row(
          children: [
            MevoraAvatar(
              name: candidate.displayName,
              image: MevoraNetworkImages.provider(candidate.avatarPhoto),
              size: 56,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${candidate.displayName}, ${candidate.age}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  MusicCompatibilityBadge(
                    score: match.musicScore,
                    sharedTracks: match.sharedTracks,
                    sharedArtists: match.sharedArtists,
                    sharedGenres: match.sharedGenres,
                    sharedTrackCount: match.sharedTrackCount,
                    sharedArtistCount: match.sharedArtistCount,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.musicSharedCounts(
                      match.sharedTrackCount,
                      match.sharedArtistCount,
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(
              MevoraIcons.chevronRight,
              size: 18,
              color: context.palette.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

String _titleCase(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

/// Shown when `getMusicAccount` itself failed. A connected user must not be
/// told to connect Spotify because the request did not come back.
class _MusicLoadFailedView extends StatelessWidget {
  const _MusicLoadFailedView({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MevoraErrorView(
      art: MevoraArt.offline,
      title: l10n.musicTitle,
      message: _musicError(l10n, controller.state.failure) ?? l10n.musicNetwork,
      onRetry: controller.state.isLoading
          ? null
          : () => unawaited(controller.load()),
    );
  }
}

String? _musicError(AppLocalizations l10n, Failure? failure) {
  if (failure == null) {
    return null;
  }
  if (failure is AuthFailure) {
    return switch (failure.kind) {
      AuthErrorKind.cancelled => l10n.musicOauthCancelled,
      AuthErrorKind.sessionExpired => l10n.musicTokenExpired,
      AuthErrorKind.network => l10n.musicNetwork,
      AuthErrorKind.notConfigured => l10n.musicNotConfigured,
      AuthErrorKind.oauth => l10n.musicApiDenied,
      _ => l10n.musicConnectError,
    };
  }
  if (failure is NetworkFailure) {
    return l10n.musicNetwork;
  }
  return L10nErrors.failure(l10n, failure);
}

Future<void> _confirmDisconnect(
  BuildContext context,
  MusicController controller,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await MevoraDialog.show(
    context,
    title: l10n.musicDisconnectConfirmTitle,
    message: l10n.musicDisconnectConfirmBody,
    confirmLabel: l10n.musicDisconnectCta,
    cancelLabel: l10n.cancel,
    confirmVariant: MevoraButtonVariant.destructive,
  );
  if (confirmed == true) {
    await controller.disconnect();
  }
}
