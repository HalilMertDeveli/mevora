import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// Header action for Boost. Ink bolt at rest; a filled ember bolt while a
/// boost is running.
class BoostButton extends StatelessWidget {
  const BoostButton({
    super.key,
    this.onPressed,
    this.isActive = false,
    this.remaining,
  });

  final VoidCallback? onPressed;
  final bool isActive;
  final Duration? remaining;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return IconButton(
      tooltip: l10n.boostTooltip,
      onPressed: onPressed,
      style: isActive
          ? IconButton.styleFrom(backgroundColor: scheme.primaryContainer)
          : null,
      icon: AnimatedSwitcher(
        duration: AppDurations.fast,
        child: Icon(
          isActive ? MevoraIcons.boostActive : MevoraIcons.boost,
          key: ValueKey(isActive),
          color: isActive ? scheme.primary : context.palette.textPrimary,
        ),
      ),
    );
  }
}

class BoostRemainingChip extends StatelessWidget {
  const BoostRemainingChip({super.key, required this.boost, required this.now});

  final Boost boost;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final remaining = boost.remaining(now);
    if (remaining <= Duration.zero) {
      return const SizedBox.shrink();
    }
    final minutes = remaining.inMinutes.clamp(1, 24 * 60);
    return MevoraPill(
      label: AppLocalizations.of(context).boostRemainingMinutes(minutes),
      icon: MevoraIcons.boostActive,
      tone: MevoraTone.accent,
      dense: true,
    );
  }
}
