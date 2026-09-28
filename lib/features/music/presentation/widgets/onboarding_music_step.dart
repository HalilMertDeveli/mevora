import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/repositories/music_repository.dart';
import 'package:mevora/features/music/presentation/controllers/public_music_controller.dart';
import 'package:mevora/features/music/presentation/pages/public_music_selection_page.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

/// The optional Spotify stage of onboarding.
///
/// Three screens in one step: the question, then — only if the member connects
/// — the selection picker. Skipping at any point calls [onSkip] and onboarding
/// carries on; Spotify is never required to finish signing up.
class OnboardingMusicStep extends StatefulWidget {
  const OnboardingMusicStep({
    super.key,
    required this.repository,
    required this.onSkip,
    required this.onFinished,
  });

  final MusicRepository repository;

  /// Continue without Spotify, or without publishing anything.
  final VoidCallback onSkip;

  /// The member published a selection; move to the next onboarding step.
  final VoidCallback onFinished;

  @override
  State<OnboardingMusicStep> createState() => _OnboardingMusicStepState();
}

class _OnboardingMusicStepState extends State<OnboardingMusicStep> {
  bool _connecting = false;
  Failure? _failure;
  bool _cancelled = false;
  PublicMusicController? _selection;

  @override
  void dispose() {
    _selection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    if (selection != null) {
      return PublicMusicSelectionPage(
        controller: selection,
        onDone: widget.onFinished,
        onSkip: widget.onSkip,
      );
    }
    return _buildQuestion(context);
  }

  Widget _buildQuestion(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.onboardingMusicTitle, style: theme.textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.onboardingMusicBody, style: theme.textTheme.bodyLarge),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.onboardingMusicSkipNote,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        if (_cancelled)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              l10n.onboardingMusicCancelled,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (_failure != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              L10nErrors.failure(l10n, _failure!),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        MevoraButton(
          label: l10n.onboardingMusicConnect,
          isLoading: _connecting,
          onPressed: _connecting ? null : () => unawaited(_connect()),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextButton(
          onPressed: _connecting ? null : widget.onSkip,
          child: Text(l10n.onboardingMusicSkip),
        ),
      ],
    );
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _failure = null;
      _cancelled = false;
    });
    final result = await widget.repository.connectSpotify();
    if (!mounted) {
      return;
    }
    result.when(
      success: (profile) {
        setState(() {
          _connecting = false;
          // Connected but with nothing to show is still a success: the taste
          // feeds compatibility even when there is nothing worth publishing.
          _selection = _buildSelection(profile);
        });
      },
      err: (failure) {
        setState(() {
          _connecting = false;
          // A cancelled authorization is not an error to apologise for — the
          // member simply backed out, and onboarding state is untouched.
          final cancelled =
              failure is AuthFailure &&
              failure.kind == AuthErrorKind.cancelled;
          _cancelled = cancelled;
          _failure = cancelled ? null : failure;
        });
      },
    );
  }

  PublicMusicController _buildSelection(MusicProfile profile) {
    return PublicMusicController(
      repository: widget.repository,
      profile: profile,
    );
  }
}
