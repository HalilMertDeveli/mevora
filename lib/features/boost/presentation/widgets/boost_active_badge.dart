import 'package:flutter/material.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

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
    final remaining = boost!.remaining(current);
    final remainingLabel = remaining.inDays >= 1
        ? l10n.boostRemainingDays(remaining.inDays)
        : remaining.inHours >= 1
        ? l10n.boostRemainingHours(remaining.inHours)
        : l10n.boostRemainingMinutes(remaining.inMinutes.clamp(1, 59));
    final label = compact
        ? l10n.boostActiveBadge
        : '${l10n.boostActiveBadge} · $remainingLabel';
    return MevoraPill(
      label: label,
      icon: MevoraIcons.boostActive,
      tone: MevoraTone.accent,
      dense: compact,
    );
  }
}
