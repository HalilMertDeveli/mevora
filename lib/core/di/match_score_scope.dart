import 'package:flutter/widgets.dart';
import 'package:mevora/features/match_score/domain/repositories/match_score_repository.dart';

class MatchScoreScope extends InheritedWidget {
  const MatchScoreScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final MatchScoreRepository repository;

  static MatchScoreRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MatchScoreScope>();
    assert(scope != null, 'MatchScoreScope not found');
    return scope!.repository;
  }

  static MatchScoreRepository? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<MatchScoreScope>()
        ?.repository;
  }

  @override
  bool updateShouldNotify(MatchScoreScope oldWidget) {
    return repository != oldWidget.repository;
  }
}
