import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/features/humor/domain/entities/humor_calibration.dart';
import 'package:mevora/features/humor/domain/entities/humor_daily_set.dart';
import 'package:mevora/features/humor/domain/repositories/humor_repository.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_daily_entry_card.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// Discover promo entry for Humor Lab (not Settings; does not change tab indexes).
///
/// Mirrors the Profile tile: it reads where the user is from the server, and
/// anyone who has not finished calibration goes through the invitation first,
/// which explains what the fifteen items are for and offers a way out.
class HumorLabDiscoverEntry extends StatefulWidget {
  const HumorLabDiscoverEntry({super.key, this.compact = false});

  /// A one-line pill for the Discover header instead of the full card.
  final bool compact;

  @override
  State<HumorLabDiscoverEntry> createState() => _HumorLabDiscoverEntryState();
}

class _HumorLabDiscoverEntryState extends State<HumorLabDiscoverEntry> {
  HumorCalibration? _calibration;
  var _requested = false;

  /// Today's daily set, read only for the full card and only once the user
  /// has finished calibration (before that the server can only say locked).
  HumorDailySet? _daily;
  var _dailyImpressionLogged = false;

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
    if (!widget.compact && calibration?.complete == true) {
      await _loadDaily(repository);
    }
  }

  Future<void> _loadDaily(HumorRepository repository) async {
    final result = await repository.getDailySet();
    if (!mounted) {
      return;
    }
    final daily = result.valueOrNull;
    if (daily == null) {
      return;
    }
    setState(() => _daily = daily);
    if (!_dailyImpressionLogged && _showsDailyCard(daily)) {
      _dailyImpressionLogged = true;
      _log(AnalyticsEvents.dailyHumorImpression, {
        'answered': daily.answeredCount,
        'total': daily.total,
      });
    }
  }

  bool _showsDailyCard(HumorDailySet daily) =>
      daily.showsEntryCard && !HumorDailyDeferral.isDeferred(daily.dayId);

  void _log(String name, Map<String, Object> parameters) {
    final analytics = BoostScope.maybeOf(context)?.analytics;
    if (analytics != null) {
      unawaited(analytics.logEvent(name, parameters: parameters));
    }
  }

  Future<void> _openDaily() async {
    await context.push(AppRoutes.humorDaily);
    if (mounted) {
      // The tour keeps its progress server-side; show where it stands now.
      await _load();
    }
  }

  void _deferDaily(HumorDailySet daily) {
    HumorDailyDeferral.defer(daily.dayId);
    _log(AnalyticsEvents.dailyHumorDeferred, {'answered': daily.answeredCount});
    setState(() {});
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
    final p = context.palette;
    if (widget.compact) {
      final progress =
          calibration != null && calibration.started && !calibration.complete
          ? ' · ${calibration.completedCount}/${calibration.totalCount}'
          : '';
      return Semantics(
        button: true,
        label: '${l10n.humorLabDiscoverCta}. $subtitle',
        excludeSemantics: true,
        child: Material(
          color: p.humorContainer,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => unawaited(_open()),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12 + 2,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(MevoraIcons.humor, size: 18, color: p.humor),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        '${l10n.humorLabTitle}$progress',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: p.onHumorContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      MevoraIcons.chevronRight,
                      size: 14,
                      color: p.onHumorContainer,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final labCard = MevoraCard(
      color: p.humorContainer,
      onTap: () => unawaited(_open()),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          const MevoraIconBadge(
            icon: MevoraIcons.humor,
            tone: MevoraTone.humor,
            size: 44,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.humorLabDiscoverCta,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: p.onHumorContainer,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: p.onHumorContainer,
                  ),
                ),
              ],
            ),
          ),
          Icon(MevoraIcons.chevronRight, color: p.onHumorContainer, size: 18),
        ],
      ),
    );
    final daily = _daily;
    if (daily == null) {
      return labCard;
    }
    if (_showsDailyCard(daily)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HumorDailyEntryCard(
            set: daily,
            onStart: () => unawaited(_openDaily()),
            onDefer: daily.completed ? null : () => _deferDaily(daily),
          ),
          const SizedBox(height: AppSpacing.sm),
          labCard,
        ],
      );
    }
    if (daily.startsTomorrow) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          labCard,
          const SizedBox(height: AppSpacing.xs),
          HumorDailyEntryCard(set: daily),
        ],
      );
    }
    return labCard;
  }
}
