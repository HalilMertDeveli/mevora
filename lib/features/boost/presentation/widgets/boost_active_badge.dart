import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/l10n/app_localizations.dart';

class BoostActiveBadge extends StatelessWidget {
  const BoostActiveBadge({
    super.key,
    this.boost,
    this.now,
    this.compact = false,
  });

  final Boost? boost;
  final DateTime? now;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final current = now ?? DateTime.now();
    final active = boost != null && boost!.isActiveAt(current);
    if (!active) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final minutes = boost!.remaining(current).inMinutes.clamp(1, 24 * 60);
    final label = compact
        ? l10n.boostActiveBadge
        : '${l10n.boostActiveBadge} · ${l10n.boostRemainingMinutes(minutes)}';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bolt_rounded,
            size: 16,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
