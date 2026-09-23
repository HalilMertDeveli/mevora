import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/music/domain/entities/public_music_profile.dart';
import 'package:mevora/features/music/presentation/controllers/public_music_controller.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

/// "Choose what appears on your profile".
///
/// Shown right after a Spotify import, and reachable later from the Music tab.
/// Everything offered here comes from the member's own top artists and tracks;
/// the page submits identifiers only.
class PublicMusicSelectionPage extends StatefulWidget {
  const PublicMusicSelectionPage({
    super.key,
    required this.controller,
    this.onDone,
    this.onSkip,
    this.skipLabel,
  });

  final PublicMusicController controller;

  /// Called after the selection is accepted by the backend.
  final VoidCallback? onDone;

  /// Called when the member moves on without publishing anything.
  final VoidCallback? onSkip;

  final String? skipLabel;

  @override
  State<PublicMusicSelectionPage> createState() =>
      _PublicMusicSelectionPageState();
}

class _PublicMusicSelectionPageState extends State<PublicMusicSelectionPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.publicMusicTitle, style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.publicMusicSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: state.hasNothingToOffer
                  // Connected, but Spotify has nothing to show yet. That is a
                  // new account, not a failure — say so and move on.
                  ? _Notice(message: l10n.publicMusicEmpty)
                  : ListView(
                      children: [
                        if (state.availableArtists.isNotEmpty) ...[
                          _SectionHeader(
                            title: l10n.publicMusicArtistsHeading,
                            counter: l10n.publicMusicArtistCount(
                              state.selectedArtistIds.length,
                              maxPublicMusicArtists,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              for (final artist in state.availableArtists)
                                _SelectableChip(
                                  label: artist.name,
                                  imageUrl: artist.image,
                                  rounded: true,
                                  selected: state.isArtistSelected(artist.id),
                                  enabled: state.canSelectArtist(artist.id),
                                  onTap: () => widget.controller.toggleArtist(
                                    artist.id,
                                  ),
                                ),
                            ],
                          ),
                          if (state.artistLimitReached)
                            _LimitHint(message: l10n.publicMusicLimitReached),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        if (state.availableTracks.isNotEmpty) ...[
                          _SectionHeader(
                            title: l10n.publicMusicTracksHeading,
                            counter: l10n.publicMusicTrackCount(
                              state.selectedTrackIds.length,
                              maxPublicMusicTracks,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              for (final track in state.availableTracks)
                                _SelectableChip(
                                  label: track.name,
                                  sublabel: track.artist.isEmpty
                                      ? null
                                      : track.artist,
                                  imageUrl: track.albumImage,
                                  selected: state.isTrackSelected(track.id),
                                  enabled: state.canSelectTrack(track.id),
                                  onTap: () => widget.controller.toggleTrack(
                                    track.id,
                                  ),
                                ),
                            ],
                          ),
                          if (state.trackLimitReached)
                            _LimitHint(message: l10n.publicMusicLimitReached),
                        ],
                      ],
                    ),
            ),
            if (state.failure != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                L10nErrors.failure(l10n, state.failure!),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            if (!state.hasNothingToOffer)
              MevoraButton(
                label: l10n.publicMusicSave,
                isLoading: state.isSaving,
                onPressed: state.hasSelection ? _save : null,
              ),
            if (widget.onSkip != null) ...[
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: state.isSaving ? null : widget.onSkip,
                child: Text(widget.skipLabel ?? l10n.onboardingMusicSkip),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _save() async {
    final saved = await widget.controller.save();
    if (saved) {
      widget.onDone?.call();
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.counter});

  final String title;
  final String counter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        Text(
          counter,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LimitHint extends StatelessWidget {
  const _LimitHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

/// A pickable artist or track. Once the limit is reached the remaining chips
/// go inert rather than silently swapping out an existing choice.
class _SelectableChip extends StatelessWidget {
  const _SelectableChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.sublabel,
    this.imageUrl,
    this.rounded = false,
  });

  final String label;
  final String? sublabel;
  final String? imageUrl;
  final bool selected;
  final bool enabled;
  final bool rounded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = MevoraNetworkImages.provider(imageUrl);
    return Semantics(
      selected: selected,
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadii.pill),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (provider != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(
                      rounded ? 28 : AppRadii.sm,
                    ),
                    child: Image(
                      image: provider,
                      width: 28,
                      height: 28,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const SizedBox(width: 28, height: 28),
                    ),
                  ),
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
                if (selected) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    Icons.check_circle,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
