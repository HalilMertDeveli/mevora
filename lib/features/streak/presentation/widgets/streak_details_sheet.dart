import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/streak/domain/entities/daily_streak.dart';
import 'package:mevora/features/streak/presentation/controllers/daily_streak_controller.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_bottom_sheet.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// What a streak is, how long this one is and how it keeps going.
///
/// Worded to reward coming back, never to shame a missed day.
abstract final class StreakDetailsSheet {
  static Future<void> show(
    BuildContext context,
    DailyStreakController controller,
  ) {
    final l10n = AppLocalizations.of(context);
    final streak = controller.streak;
    if (streak != null) {
      controller.analytics.detailsViewed(streak);
    }
    return MevoraBottomSheet.show<void>(
      context,
      title: l10n.streakTitle,
      scrollable: true,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final current = controller.streak ?? streak;
          if (current == null) {
            return const SizedBox.shrink();
          }
          return StreakDetailsContent(streak: current);
        },
      ),
    );
  }
}

class StreakDetailsContent extends StatelessWidget {
  const StreakDetailsContent({super.key, required this.streak});

  final DailyStreak streak;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.palette;
    return Column(
      key: const ValueKey('streak-details'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const MevoraIconBadge(
              icon: MevoraIcons.streak,
              tone: MevoraTone.accent,
              size: 56,
              circle: true,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.streakDays(streak.currentStreak),
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.streakDetailsBody(streak.currentStreak),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        StreakWeekRow(streak: streak),
        const SizedBox(height: AppSpacing.md),
        MevoraCard(
          emphasis: MevoraCardEmphasis.quiet,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatLine(
                icon: MevoraIcons.star,
                text: l10n.streakLongest(streak.longestStreak),
              ),
              const SizedBox(height: AppSpacing.sm),
              _StatLine(
                icon: MevoraIcons.check,
                text: l10n.streakTotalDays(streak.totalCheckInDays),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.streakHowItWorks,
          style: theme.textTheme.bodySmall?.copyWith(
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.streakMissedDayNote,
          style: theme.textTheme.bodySmall?.copyWith(
            color: palette.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ExcludeSemantics(
          child: Icon(icon, size: 18, color: context.palette.textSecondary),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

/// The last seven days ending on the streak's day, with the days the current
/// streak covers marked. Derived from the counters — no per-day history is
/// stored anywhere.
class StreakWeekRow extends StatelessWidget {
  const StreakWeekRow({super.key, required this.streak});

  final DailyStreak streak;

  static const int days = 7;

  /// Which of the last seven days, oldest first, the current streak covers.
  static List<bool> coveredDays(int currentStreak) => [
    for (var i = days - 1; i >= 0; i--) i < currentStreak,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final today = streak.day;
    if (today == null) {
      return const SizedBox.shrink();
    }
    final covered = coveredDays(streak.currentStreak);
    final visited = covered.where((c) => c).length;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final accent = mevoraToneColors(context, MevoraTone.accent);
    final palette = context.palette;
    return Semantics(
      container: true,
      label: l10n.streakWeekSemantics(visited),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.streakLastSevenDays, style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (var i = 0; i < days; i++)
                Expanded(
                  child: _DayDot(
                    label: DateFormat.E(
                      locale,
                    ).format(today.subtract(Duration(days: days - 1 - i))),
                    active: covered[i],
                    isToday: i == days - 1,
                    fill: accent.strong,
                    empty: palette.surfaceMuted,
                    onFill: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.label,
    required this.active,
    required this.isToday,
    required this.fill,
    required this.empty,
    required this.onFill,
  });

  final String label;
  final bool active;
  final bool isToday;
  final Color fill;
  final Color empty;
  final Color onFill;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: active ? fill : empty,
            shape: BoxShape.circle,
            border: isToday && !active
                ? Border.all(color: palette.borderStrong)
                : null,
          ),
          alignment: Alignment.center,
          // The mark is a shape as well as a colour, so the row reads
          // without relying on colour alone.
          child: active
              ? Icon(MevoraIcons.streak, size: 16, color: onFill)
              : null,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: isToday ? palette.textPrimary : palette.textSecondary,
            fontWeight: isToday ? FontWeight.w700 : null,
          ),
        ),
      ],
    );
  }
}
