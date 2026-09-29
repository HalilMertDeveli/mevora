import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/streak_scope.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/streak/domain/entities/daily_streak.dart';
import 'package:mevora/features/streak/presentation/controllers/daily_streak_controller.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_bottom_sheet.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// Shows the new-day celebration once the app shell is on screen.
///
/// It fires only for a check-in the backend credited, and takes the result
/// from the controller so it can never be shown twice. A same-day reopen or
/// a sign-out and back in never produces one.
class StreakCelebrationHost extends StatefulWidget {
  const StreakCelebrationHost({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 700),
  });

  final Widget child;

  /// Lets the screen underneath paint first, so the moment reads as a reward
  /// on arriving rather than something in the way of arriving.
  final Duration delay;

  @override
  State<StreakCelebrationHost> createState() => _StreakCelebrationHostState();
}

class _StreakCelebrationHostState extends State<StreakCelebrationHost> {
  DailyStreakController? _controller;
  Timer? _timer;
  bool _showing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = StreakScope.controllerOf(context);
    if (identical(controller, _controller)) {
      return;
    }
    _controller?.removeListener(_onChanged);
    _controller = controller;
    controller?.addListener(_onChanged);
    _onChanged();
  }

  void _onChanged() {
    final controller = _controller;
    if (controller == null ||
        controller.pendingCelebration == null ||
        _showing ||
        _timer != null) {
      return;
    }
    _timer = Timer(widget.delay, () {
      _timer = null;
      unawaited(_show());
    });
  }

  Future<void> _show() async {
    final controller = _controller;
    if (!mounted || controller == null || _showing) {
      return;
    }
    final result = controller.takeCelebration();
    if (result == null) {
      return;
    }
    _showing = true;
    try {
      await MevoraBottomSheet.show<void>(
        context,
        scrollable: true,
        child: StreakCelebrationContent(result: result),
      );
    } finally {
      _showing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class StreakCelebrationContent extends StatelessWidget {
  const StreakCelebrationContent({super.key, required this.result});

  final DailyCheckInResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final count = result.streak.currentStreak;
    final (title, body) = switch (result.status) {
      CheckInStatus.started => (
        l10n.streakStartedTitle,
        l10n.streakStartedBody,
      ),
      CheckInStatus.reset => (
        l10n.streakRestartedTitle,
        l10n.streakRestartedBody,
      ),
      _ => (l10n.streakDays(count), l10n.streakContinuedBody),
    };
    final emphasis = result.milestone || result.newPersonalBest;
    return Column(
      key: const ValueKey('streak-celebration'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: AppSpacing.sm),
        _Ember(count: count, large: emphasis),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          body,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: context.palette.textSecondary,
          ),
        ),
        if (emphasis) ...[
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              if (result.newPersonalBest)
                MevoraPill(
                  label: l10n.streakPersonalBest,
                  icon: MevoraIcons.star,
                  tone: MevoraTone.premium,
                ),
              if (result.milestone)
                MevoraPill(
                  label: l10n.streakMilestone,
                  icon: MevoraIcons.streak,
                  tone: MevoraTone.accent,
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        MevoraButton(
          label: l10n.streakCelebrationDismiss,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

/// The ember with the day count. Pops in once; holds still under reduced
/// motion.
class _Ember extends StatelessWidget {
  const _Ember({required this.count, required this.large});

  final int count;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colors = mevoraToneColors(context, MevoraTone.accent);
    final size = large ? 104.0 : 88.0;
    final badge = ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: colors.bg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(MevoraIcons.streak, size: size * 0.4, color: colors.strong),
            MediaQuery.withNoTextScaling(
              child: Text(
                '$count',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colors.fg,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return badge;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: badge,
    );
  }
}
