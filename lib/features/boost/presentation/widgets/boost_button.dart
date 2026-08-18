import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_press_scale.dart';

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
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.boostTooltip,
      child: MevoraPressScale(
        enabled: onPressed != null,
        child: IconButton(
          tooltip: l10n.boostTooltip,
          onPressed: onPressed,
          icon: AnimatedSwitcher(
            duration: AppDurations.short,
            child: Icon(
              isActive ? Icons.bolt : Icons.bolt_outlined,
              key: ValueKey(isActive),
              color: isActive ? colors.secondary : colors.primary,
            ),
          ),
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
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        AppLocalizations.of(context).boostRemainingMinutes(minutes),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
