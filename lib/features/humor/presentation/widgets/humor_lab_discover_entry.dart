import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/humor/domain/entities/humor_calibration.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Discover promo entry for Humor Lab (not Settings; does not change tab indexes).
///
/// Mirrors the Profile tile: it reads where the user is from the server, and
/// anyone who has not finished calibration goes through the invitation first,
/// which explains what the fifteen items are for and offers a way out.
class HumorLabDiscoverEntry extends StatefulWidget {
  const HumorLabDiscoverEntry({super.key});

  @override
  State<HumorLabDiscoverEntry> createState() => _HumorLabDiscoverEntryState();
}

class _HumorLabDiscoverEntryState extends State<HumorLabDiscoverEntry> {
  HumorCalibration? _calibration;
  var _requested = false;

  bool get _enabled =>
      AppScope.maybeOf(context)?.config.featureFlags.humorLabEnabled == true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested || !_enabled) {
      return;
    }
    _requested = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    final repository = HumorScope.maybeOf(context);
    if (repository == null) {
      return;
    }
    final result = await repository.getProfile();
    if (!mounted) {
      return;
    }
    final calibration = result.valueOrNull?.calibration;
    if (calibration != null) {
      setState(() => _calibration = calibration);
    }
  }

  Future<void> _open() async {
    final complete = _calibration?.complete == true;
    await context.push(
      complete ? AppRoutes.humorLab : AppRoutes.humorCalibration,
    );
    if (mounted) {
      // Progress may have moved while the user was away.
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final calibration = _calibration;
    final String subtitle;
    if (calibration == null || !calibration.started) {
      subtitle = l10n.humorProfileEntryNotStarted;
    } else if (calibration.complete) {
      subtitle = l10n.humorLabSubtitle;
    } else {
      subtitle = l10n.humorProfileEntryInProgress(
        calibration.completedCount,
        calibration.totalCount,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          onTap: () => unawaited(_open()),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(
                  Icons.theater_comedy_outlined,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.humorLabDiscoverCta,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer
                              .withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
