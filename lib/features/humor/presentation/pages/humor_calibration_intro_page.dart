import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/di/relationship_learning_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/humor/domain/entities/humor_calibration.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

/// Invitation to the initial humor calibration.
///
/// Shown once the core profile is viable, as a personalization step — not as
/// an onboarding gate. Skipping must leave the app fully usable, so this
/// screen never blocks: every exit leads somewhere.
///
/// Deliberately speaks in product terms. "Anchor", "adaptive", "exploration",
/// "vector" and "calibration version" are internal words and stay internal.
class HumorCalibrationIntroPage extends StatefulWidget {
  const HumorCalibrationIntroPage({super.key, this.onExit});

  /// Where to go when the user skips. Defaults to back to the opener, or to
  /// discovery, which is where post-onboarding personalization hands off.
  final VoidCallback? onExit;

  @override
  State<HumorCalibrationIntroPage> createState() =>
      _HumorCalibrationIntroPageState();
}

class _HumorCalibrationIntroPageState extends State<HumorCalibrationIntroPage> {
  HumorCalibration _calibration = HumorCalibration.empty;
  bool _loading = true;
  bool _requested = false;
  bool _logged = false;
  bool _startLogged = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) {
      return;
    }
    _requested = true;
    unawaited(_load());
  }

  /// Progress is read from the server, never assumed. A user who rated nine
  /// items on another device must be invited to continue, not to restart.
  Future<void> _load() async {
    final repository = HumorScope.maybeOf(context);
    if (repository == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }
    final result = await repository.getProfile();
    if (!mounted) {
      return;
    }
    setState(() {
      // A failed refresh keeps what was already known rather than claiming
      // the user has not started.
      _calibration = result.valueOrNull?.calibration ?? _calibration;
      _loading = false;
    });
    if (!_logged) {
      _logged = true;
      // Analytics parameters must be String or num; a bool fails the
      // firebase_analytics assertion and the event is lost.
      _log(AnalyticsEvents.humorCalibrationImpression, {
        'resumed': _calibration.started ? 1 : 0,
      });
    }
  }

  void _log(String name, [Map<String, Object>? parameters]) {
    final analytics = BoostScope.maybeOf(context)?.analytics;
    if (analytics == null) {
      return;
    }
    unawaited(analytics.logEvent(name, parameters: parameters));
  }

  /// Back to wherever the invitation was opened from (Profile, Discover), or
  /// on to discovery when it was the only screen (after onboarding).
  void _exit() {
    final onExit = widget.onExit;
    if (onExit != null) {
      onExit();
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
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(AppRoutes.discovery);
    }
  }

  Future<void> _start() async {
    // The one place calibration "starts": the Lab itself only reports
    // progress and completion, so reopening it never re-counts a start.
    if (!_startLogged) {
      _startLogged = true;
      _log(AnalyticsEvents.humorCalibrationStarted, {
        'resumed': _calibration.started ? 1 : 0,
      });
    }
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      return;
    }
    // Pushed, not gone to: the Lab must be able to close back to here.
    await router.push<void>(AppRoutes.humorLab);
    if (!mounted) {
      return;
    }
    // Back from the Lab part-way through: show where the user now is.
    await _load();
  }

  Future<void> _skip() async {
    // No humor profile is fabricated here. The user simply has none yet, and
    // humor compatibility will correctly report itself as unavailable.
    _log(AnalyticsEvents.humorCalibrationSkipped, {
      'completed': _calibration.completedCount,
    });
    // During a new member's first run the skip is recorded on the server, so
    // the journey moves on to Relationship Learning and never loops back
    // here. The lab itself stays open for later.
    final learning = RelationshipLearningScope.maybeOf(context);
    final journey = learning?.journey;
    if (learning != null && journey?.stage == JourneyStage.humor) {
      await learning.repository.skipOnboardingHumor();
      await journey!.refresh();
    }
    if (mounted) {
      _exit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final resuming = _calibration.started && !_calibration.complete;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Semantics(
                // The illustration is decorative; the heading carries meaning.
                excludeSemantics: true,
                child: const Center(
                  child: MevoraSpot(art: MevoraArt.humor, size: 140),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.humorCalibrationIntroTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.humorCalibrationIntroBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (resuming)
                Column(
                  children: [
                    Text(
                      l10n.humorCalibrationProgress(
                        _calibration.completedCount,
                        _calibration.totalCount,
                      ),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.humorCalibrationResumeNote,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                )
              else if (_calibration.totalCount > 0)
                Text(
                  l10n.humorCalibrationIntroMeta(_calibration.totalCount),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const Spacer(),
              MevoraButton(
                label: resuming
                    ? l10n.humorCalibrationResume
                    : l10n.humorCalibrationStart,
                onPressed: _loading ? null : () => unawaited(_start()),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Skip never waits on the server: leaving must always work.
              MevoraButton(
                label: l10n.humorCalibrationSkip,
                variant: MevoraButtonVariant.ghost,
                onPressed: _skip,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
