import 'package:flutter/widgets.dart';
import 'package:mevora/features/matching_streak/domain/repositories/matching_streak_repository.dart';

class MatchingStreakScope extends InheritedWidget {
  const MatchingStreakScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final MatchingStreakRepository repository;

  static MatchingStreakRepository of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<MatchingStreakScope>();
    assert(scope != null, 'MatchingStreakScope not found');
    return scope!.repository;
  }

  static MatchingStreakRepository? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<MatchingStreakScope>()
        ?.repository;
  }

  @override
  bool updateShouldNotify(MatchingStreakScope oldWidget) {
    return repository != oldWidget.repository;
  }
}
