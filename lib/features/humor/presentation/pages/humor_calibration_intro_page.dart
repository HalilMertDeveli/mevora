import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/humor/domain/entities/humor_calibration.dart';
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

  /// Where to go when the user starts, finishes or skips. Defaults to
  /// discovery, which is where post-onboarding personalization hands off.
  final VoidCallback? onExit;

  @override
  State<HumorCalibrationIntroPage> createState() =>
      _HumorCalibrationIntroPageState();
}

class _HumorCalibrationIntroPageState extends State<HumorCalibrationIntroPage> {
  HumorCalibration _calibration = HumorCalibration.empty;
  bool _loading = true;
  bool _logged = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loading) {
      return;
    }
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
      _calibration = result.valueOrNull?.calibration ?? HumorCalibration.empty;
      _loading = false;
    });
    if (!_logged) {
      _logged = true;
      _log(AnalyticsEvents.humorCalibrationImpression, {
        'resumed': _calibration.started,
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

  void _exit() {
    final onExit = widget.onExit;
    if (onExit != null) {
      onExit();
      return;
    }
    if (context.mounted) {
      context.go(AppRoutes.discovery);
    }
  }

  void _start() {
    _log(AnalyticsEvents.humorCalibrationStarted, {
      'resumed': _calibration.started,
    });
    context.go(AppRoutes.humorLab);
  }

  void _skip() {
    // No humor profile is fabricated here. The user simply has none yet, and
    // humor compatibility will correctly report itself as unavailable.
    _log(AnalyticsEvents.humorCalibrationSkipped, {
      'completed': _calibration.completedCount,
    });
    _exit();
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
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _loading ? null : _skip,
                  child: Text(l10n.humorCalibrationSkip),
                ),
              ),
              const Spacer(),
              Semantics(
                // The illustration is decorative; the heading carries meaning.
                excludeSemantics: true,
                child: Icon(
                  Icons.theater_comedy_outlined,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.humorCalibrationIntroTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
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
              else
                Text(
                  l10n.humorCalibrationIntroMeta,
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
                onPressed: _loading ? null : _start,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: _loading ? null : _skip,
                child: Text(l10n.humorCalibrationSkip),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
