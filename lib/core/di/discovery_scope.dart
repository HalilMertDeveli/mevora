import 'package:flutter/widgets.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';

class DiscoveryScope extends InheritedWidget {
  const DiscoveryScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final DiscoveryRepository repository;

  static DiscoveryRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DiscoveryScope>();
    assert(scope != null, 'DiscoveryScope not found');
    return scope!.repository;
  }

  static DiscoveryRepository? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DiscoveryScope>()?.repository;
  }

  @override
  bool updateShouldNotify(DiscoveryScope oldWidget) {
    return repository != oldWidget.repository;
  }
}
