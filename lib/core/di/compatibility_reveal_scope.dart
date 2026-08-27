import 'package:flutter/widgets.dart';
import 'package:mevora/features/compatibility/data/repositories/compatibility_reveal_repository.dart';

class CompatibilityRevealScope extends InheritedWidget {
  const CompatibilityRevealScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final CompatibilityRevealRepository repository;

  static CompatibilityRevealRepository? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CompatibilityRevealScope>()
        ?.repository;
  }

  @override
  bool updateShouldNotify(CompatibilityRevealScope oldWidget) {
    return repository != oldWidget.repository;
  }
}
