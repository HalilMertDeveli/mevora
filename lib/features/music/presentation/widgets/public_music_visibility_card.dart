import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/repositories/music_repository.dart';
import 'package:mevora/features/music/presentation/controllers/public_music_controller.dart';
import 'package:mevora/features/music/presentation/pages/public_music_selection_page.dart';
import 'package:mevora/features/music/presentation/widgets/public_music_taste_section.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';

/// Owner-facing control for the Music Taste section.
///
/// Connection and visibility are separate states. Turning this off hides the
/// selection from other members but keeps Spotify connected, so the imported
/// taste still feeds music compatibility. Only Disconnect removes the data.
class PublicMusicVisibilityCard extends StatefulWidget {
  const PublicMusicVisibilityCard({
    super.key,
    required this.repository,
    required this.profile,
    this.onChanged,
  });

  final MusicRepository repository;
  final MusicProfile profile;

  /// Called after a successful publish so the host can refresh its own state.
  final VoidCallback? onChanged;

  @override
  State<PublicMusicVisibilityCard> createState() =>
      _PublicMusicVisibilityCardState();
}

class _PublicMusicVisibilityCardState extends State<PublicMusicVisibilityCard> {
  bool _busy = false;

  /// What the member just asked for, while the write is still in flight.
  ///
  /// The switch showed the stored value until the round trip finished. Against
  /// a real backend that is a second or two of a control that does not move
  /// when tapped, which reads as broken — so the position follows the tap
  /// immediately and only rolls back if the write actually fails.
  bool? _pendingEnabled;

  /// Why the last visibility change did not stick, if it did not.
  String? _lastError;

  @override
  void didUpdateWidget(PublicMusicVisibilityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Once the host hands back a reloaded profile, the stored value is the
    // truth again.
    if (oldWidget.profile.publicProfile.enabled !=
        widget.profile.publicProfile.enabled) {
      _pendingEnabled = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final published = widget.profile.publicProfile;
    final shown = _pendingEnabled ?? published.enabled;

    return MevoraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.publicMusicVisibilityTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Switch(
                value: shown,
                // A hidden card has no content by definition, so asking
                // hasContent here left the switch dead exactly where it was
                // needed. What matters is whether there is a selection to
                // show at all.
                onChanged: _busy || !published.hasSelection
                    ? null
                    : (value) => unawaited(_setEnabled(value)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.publicMusicVisibilityBody,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          // Follows the switch rather than the stored value, so the preview
          // and the control never disagree while a write is in flight.
          if (shown && published.hasSelection) ...[
            const SizedBox(height: AppSpacing.md),
            PublicMusicTasteSection(
              profile: published.enabled
                  ? published
                  : published.copyWith(enabled: true),
            ),
          ] else if (published.hasSelection) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.publicMusicHiddenNotice,
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (_lastError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _lastError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          MevoraButton(
            label: l10n.publicMusicEditCta,
            variant: MevoraButtonVariant.secondary,
            onPressed: _busy ? null : () => unawaited(_edit(context)),
          ),
        ],
      ),
    );
  }

  /// Flips visibility without reopening the picker: the published selection is
  /// re-sent unchanged, so the server keeps it and only the flag moves.
  Future<void> _setEnabled(bool enabled) async {
    setState(() {
      _busy = true;
      _pendingEnabled = enabled;
      _lastError = null;
    });
    final published = widget.profile.publicProfile;
    final result = await widget.repository.updatePublicMusicProfile(
      enabled: enabled,
      artistIds: published.artistIds,
      trackIds: published.trackIds,
    );
    if (!mounted) {
      return;
    }
    final failure = result.failureOrNull;
    setState(() {
      _busy = false;
      // A failed write must not look like a successful one: roll the switch
      // back to what is actually stored and say why.
      if (failure != null) {
        _pendingEnabled = null;
      }
      _lastError = failure?.message;
    });
    if (failure == null) {
      widget.onChanged?.call();
    }
  }

  Future<void> _edit(BuildContext context) async {
    final controller = PublicMusicController(
      repository: widget.repository,
      profile: widget.profile,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.screenPadding,
          right: AppSpacing.screenPadding,
          top: AppSpacing.screenPadding,
          bottom:
              MediaQuery.of(sheetContext).viewInsets.bottom +
              AppSpacing.screenPadding,
        ),
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.75,
          child: PublicMusicSelectionPage(
            controller: controller,
            onDone: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ),
    );
    controller.dispose();
    if (mounted) {
      widget.onChanged?.call();
    }
  }
}
