import 'package:flutter/widgets.dart';
import 'package:mevora/features/streak/presentation/controllers/daily_streak_controller.dart';

/// Single access point for the member's daily streak. Read-only: nothing
/// reachable from here can set a streak — the backend owns it.
class StreakScope extends InheritedNotifier<DailyStreakController> {
  const StreakScope({
    super.key,
    required DailyStreakController controller,
    required super.child,
  }) : super(notifier: controller);

  DailyStreakController get controller => notifier!;

  /// The controller without subscribing to its changes — for widgets that
  /// listen themselves. Null when streaks are not wired (tests, previews).
  static DailyStreakController? controllerOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<StreakScope>()?.notifier;
  }
}
