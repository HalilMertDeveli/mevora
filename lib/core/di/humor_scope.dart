import 'package:flutter/widgets.dart';
import 'package:mevora/features/humor/domain/repositories/humor_repository.dart';

class HumorScope extends InheritedWidget {
  const HumorScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final HumorRepository repository;

  static HumorRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<HumorScope>();
    assert(scope != null, 'HumorScope not found');
    return scope!.repository;
  }

  static HumorRepository? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<HumorScope>()?.repository;
  }

  @override
  bool updateShouldNotify(HumorScope oldWidget) {
    return repository != oldWidget.repository;
  }
}
