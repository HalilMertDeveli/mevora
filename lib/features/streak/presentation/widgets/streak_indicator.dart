import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/streak_scope.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/streak/presentation/widgets/streak_details_sheet.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// The compact ember + day count in the app bar. Tapping it opens the streak
/// details. Renders nothing until the backend has confirmed a streak, so it
/// never shows a number the server did not give.
class StreakIndicator extends StatelessWidget {
  const StreakIndicator({super.key});

  static const Key tapTargetKey = ValueKey('streak-indicator');

  @override
  Widget build(BuildContext context) {
    final controller = StreakScope.controllerOf(context);
    if (controller == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final streak = controller.streak;
        if (streak == null || streak.currentStreak <= 0) {
          return const SizedBox.shrink();
        }
        return _IndicatorChip(
          count: streak.currentStreak,
          onTap: () => StreakDetailsSheet.show(context, controller),
        );
      },
    );
  }
}

class _IndicatorChip extends StatelessWidget {
  const _IndicatorChip({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = mevoraToneColors(context, MevoraTone.accent);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final label = Text(
      '$count',
      key: ValueKey(count),
      maxLines: 1,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: colors.fg,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    );
    // The app bar has a fixed height; past this the chip would clip rather
    // than grow, and the full-size number is one tap away in the sheet.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.5,
      child: Semantics(
        button: true,
        label: l10n.streakIndicatorSemantics(count),
        excludeSemantics: true,
        child: Tooltip(
          message: l10n.streakIndicatorTooltip,
          excludeFromSemantics: true,
          child: InkWell(
            key: StreakIndicator.tapTargetKey,
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: AppSpacing.minTouchTarget,
                minHeight: AppSpacing.minTouchTarget,
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s12 - 2,
                    vertical: AppSpacing.xs + 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.bg,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(MevoraIcons.streak, size: 18, color: colors.strong),
                      const SizedBox(width: AppSpacing.xs),
                      if (reduceMotion)
                        label
                      else
                        AnimatedSwitcher(
                          duration: AppDurations.normal,
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(scale: animation, child: child),
                          child: label,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
