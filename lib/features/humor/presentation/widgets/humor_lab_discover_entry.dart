import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/features/humor/domain/entities/humor_calibration.dart';
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
    return MevoraCard(
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
  }
}
