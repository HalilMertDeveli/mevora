import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/domain/services/humor_profile_display.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

/// What the user gets for finishing calibration.
///
/// The goal is "Mevora actually learned something about me", not "here is a
/// number". So: a handful of named traits, a sentence that reads like an
/// observation, and no percentages. The precise vector stays server-side.
class HumorCalibrationResultPage extends StatefulWidget {
  const HumorCalibrationResultPage({super.key, this.onDone});

  final VoidCallback? onDone;

  @override
  State<HumorCalibrationResultPage> createState() =>
      _HumorCalibrationResultPageState();
}

class _HumorCalibrationResultPageState
    extends State<HumorCalibrationResultPage> {
  UserHumorProfile? _profile;
  Failure? _failure;

  /// No humor backend is wired in at all — nothing to retry, only a way on.
  var _unavailable = false;
  var _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) {
      return;
    }
    _requested = true;
    if (HumorScope.maybeOf(context) == null) {
      // Not an endless spinner: say so and offer the way on.
      _unavailable = true;
      return;
    }
    unawaited(_load());
  }

  Future<void> _load() async {
    final repository = HumorScope.maybeOf(context);
    if (repository == null) {
      setState(() => _unavailable = true);
      return;
    }
    if (_failure != null) {
      setState(() => _failure = null);
    }
    // Detailed: the result screen is the one place the owner sees their own
    // dimensions. It is still only ever their own.
    final result = await repository.getProfile(detailed: true);
    if (!mounted) {
      return;
    }
    final profile = result.valueOrNull;
    if (profile == null) {
      // Never dress a failed load up as a finished, empty profile.
      setState(() => _failure = result.failureOrNull);
      return;
    }
    setState(() => _profile = profile);
    final analytics = BoostScope.maybeOf(context)?.analytics;
    unawaited(
      analytics?.logEvent(
        AnalyticsEvents.humorProfileViewed,
        parameters: const {'source': 'calibration_result'},
      ),
    );
  }

  void _done() {
    final onDone = widget.onDone;
    if (onDone != null) {
      onDone();
      return;
    }
    if (!context.mounted) {
      return;
    }
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      unawaited(Navigator.of(context).maybePop());
      return;
    }
    router.go(AppRoutes.discovery);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final profile = _profile;

    if (_unavailable) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.humorProfileTitle)),
        body: MevoraErrorView(onRetry: _done, retryLabel: l10n.humorResultDone),
      );
    }

    final failure = _failure;
    if (failure != null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.humorProfileTitle)),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: MevoraErrorView(
                  message: L10nErrors.failure(l10n, failure),
                  onRetry: () => unawaited(_load()),
                  retryLabel: l10n.humorTryAgain,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                child: TextButton(
                  onPressed: _done,
                  child: Text(l10n.humorResultDone),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.humorProfileTitle)),
        body: MevoraLoading.page(message: l10n.humorProfileTitle),
      );
    }

    final vibes = HumorProfileDisplay.visibleTopVibes(profile, max: 4);
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.humorResultTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          children: [
            Text(
              l10n.humorResultSubtitle,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final vibe in vibes) ...[
              _VibeBar(vibe: vibe),
              const SizedBox(height: AppSpacing.md),
            ],
            const SizedBox(height: AppSpacing.sm),
            // The summary is the payoff of calibration, so it reads as a
            // quote in the display face rather than as body copy.
            MevoraCard(
              color: p.humorContainer,
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Text(
                HumorProfileDisplay.summarySentence(l10n, profile),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: p.onHumorContainer,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              // Calibration is a milestone, not an ending — say so, so the
              // user is not surprised when the profile shifts later.
              l10n.humorResultEvolvesNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            MevoraButton(label: l10n.humorResultDone, onPressed: _done),
            const SizedBox(height: AppSpacing.sm),
            MevoraButton(
              label: l10n.humorResultKeepGoing,
              variant: MevoraButtonVariant.ghost,
              onPressed: () => context.push(AppRoutes.humorLab),
            ),
          ],
        ),
      ),
    );
  }
}

/// One trait: name, strength word, and a bar.
///
/// The bar and the word carry the same information, so the screen is readable
/// without relying on the bar's length alone.
class _VibeBar extends StatelessWidget {
  const _VibeBar({required this.vibe});

  final HumorVibe vibe;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final label = HumorProfileDisplay.categoryLabel(l10n, vibe.category);
    final strength = HumorProfileDisplay.strengthOf(vibe.value);
    final strengthText = HumorProfileDisplay.strengthLabel(l10n, strength);

    return Semantics(
      label: label,
      value: strengthText,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: theme.textTheme.titleMedium),
              Text(
                strengthText,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // The bar is decoration; its own semantics would read the raw
          // 0-100 value aloud. The strength word above is the announcement.
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: LinearProgressIndicator(
                value: (vibe.value / 100).clamp(0.0, 1.0),
                minHeight: 8,
                color: context.palette.humor,
                backgroundColor: context.palette.humorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
