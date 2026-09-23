import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/music_scope.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/discovery/presentation/pages/discovery_profile_details_page.dart';
import 'package:mevora/features/music/domain/entities/music_track.dart';
import 'package:mevora/features/music/domain/entities/same_taste_match.dart';
import 'package:mevora/features/music/presentation/controllers/music_controller.dart';
import 'package:mevora/features/music/presentation/widgets/music_compatibility_badge.dart';
import 'package:mevora/features/music/presentation/widgets/public_music_visibility_card.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_motion_size.dart';
import 'package:mevora/shared/animations/mevora_page_transitions.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

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
          icon: Icons.library_music_outlined,
          riveAsset: MevoraRiveAssets.empty,
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
                    asset: MevoraRiveAssets.musicAnalyzing,
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
    final accentSize = MevoraMotionSize.accent(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: [
        Center(
          child: MevoraRiveAnimation(
            asset: connecting
                ? MevoraRiveAssets.spotifyConnecting
                : MevoraRiveAssets.spotifyIdle,
            width: accentSize,
            height: accentSize,
            semanticsLabel: connecting ? l10n.musicConnecting : l10n.musicTitle,
            fallback: Icon(
              Icons.library_music_outlined,
              size: 40,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.musicUnconnectedCopy,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.musicPrivacyNotice,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            error,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        MevoraButton(
          label: l10n.musicConnectCta,
          icon: Icons.headphones_outlined,
          isLoading: connecting,
          onPressed: connecting ? null : controller.connectSpotify,
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
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: [
        MevoraCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.musicConnected, style: theme.textTheme.titleMedium),
              if (profile.displayName != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(profile.displayName!, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: AppSpacing.md),
              MevoraButton(
                label: l10n.musicRefresh,
                variant: MevoraButtonVariant.secondary,
                isLoading: syncing,
                onPressed: state.canRefresh && !syncing
                    ? controller.syncTaste
                    : null,
              ),
              if (!state.canRefresh) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.musicRefreshCooldown,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              MevoraButton(
                label: l10n.musicDisconnectCta,
                variant: MevoraButtonVariant.ghost,
                onPressed: syncing
                    ? null
                    : () => unawaited(_confirmDisconnect(context, controller)),
              ),
            ],
          ),
        ),
        if (syncing) ...[
          const SizedBox(height: AppSpacing.md),
          MevoraLoading(
            message: l10n.musicSyncing,
            asset: MevoraRiveAssets.musicAnalyzing,
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            error,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        // Connection and visibility are separate: this card publishes or
        // hides the selection without touching the Spotify connection.
        if (repository != null) ...[
          const SizedBox(height: AppSpacing.md),
          PublicMusicVisibilityCard(
            repository: repository,
            profile: profile,
            onChanged: () => unawaited(controller.load()),
          ),
        ],
        if (profile.hasLimitedData) ...[
          const SizedBox(height: AppSpacing.md),
          Text(l10n.musicLimitedData, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.musicProfileTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        if (profile.genres.isEmpty)
          Text(l10n.musicSameTasteEmpty, style: theme.textTheme.bodyMedium)
        else
          ...profile.genres.map((genre) => _GenreBar(genre: genre)),
        if (profile.topArtists.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: profile.topArtists
                .take(6)
                .map(
                  (artist) =>
                      _TasteChip(label: artist.name, image: artist.image),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Text(l10n.musicSameTasteTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        if (state.sameTaste.isEmpty)
          MevoraEmptyState(
            icon: Icons.people_outline,
            riveAsset: MevoraRiveAssets.emptyProfiles,
            title: l10n.musicSameTasteTitle,
            message: l10n.musicSameTasteEmpty,
          )
        else
          ...state.sameTaste.map(
            (match) => _SameTasteTile(
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
          ),
        const SizedBox(height: AppSpacing.xl),
        Text(l10n.musicWeeklyTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        if (state.weekly.isEmpty)
          Text(l10n.musicWeeklyEmpty, style: theme.textTheme.bodyMedium)
        else
          ...state.weekly.tracks.map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _Cover(url: item.track.albumImage),
              title: Text(item.track.name),
              subtitle: Text(item.track.artist),
              trailing: Text('${item.playCount}'),
            ),
          ),
      ],
    );
  }
}

class _GenreBar extends StatelessWidget {
  const _GenreBar({required this.genre});

  final GenreShare genre;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(genre.name, style: theme.textTheme.bodyMedium),
              ),
              Text('${genre.percent}%', style: theme.textTheme.labelMedium),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: (genre.percent / 100).clamp(0, 1),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}

class _TasteChip extends StatelessWidget {
  const _TasteChip({required this.label, this.image});

  final String label;
  final String? image;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: _Cover(url: image, size: 24),
      label: Text(label),
    );
  }
}

class _SameTasteTile extends StatelessWidget {
  const _SameTasteTile({required this.match, required this.onTap});

  final SameTasteMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final candidate = match.candidate;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: MevoraCard(
        onTap: onTap,
        child: Row(
          children: [
            _Cover(url: candidate.photoUrl, size: 56),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${candidate.displayName}, ${candidate.age}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  MusicCompatibilityBadge(
                    score: match.musicScore,
                    sharedTracks: match.sharedTracks,
                    sharedArtists: match.sharedArtists,
                    sharedGenres: match.sharedGenres,
                    sharedTrackCount: match.sharedTrackCount,
                    sharedArtistCount: match.sharedArtistCount,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.musicSharedCounts(
                      match.sharedTrackCount,
                      match.sharedArtistCount,
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({this.url, this.size = 48});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: SizedBox(
        width: size,
        height: size,
        child:
            url == null ||
                url!.isEmpty ||
                MevoraNetworkImages.provider(url) == null
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: const Icon(Icons.album_outlined),
              )
            : Image(
                image: MevoraNetworkImages.provider(url)!,
                fit: BoxFit.cover,
              ),
      ),
    );
  }
}

/// Shown when `getMusicAccount` itself failed. A connected user must not be
/// told to connect Spotify because the request did not come back.
class _MusicLoadFailedView extends StatelessWidget {
  const _MusicLoadFailedView({required this.controller});

  final MusicController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _musicError(l10n, controller.state.failure) ?? l10n.musicNetwork,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          MevoraButton(
            label: l10n.retry,
            isLoading: controller.state.isLoading,
            onPressed: () => unawaited(controller.load()),
          ),
        ],
      ),
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
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.musicDisconnectConfirmTitle),
      content: Text(l10n.musicDisconnectConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.musicDisconnectCta),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await controller.disconnect();
  }
}
