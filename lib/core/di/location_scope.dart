import 'package:flutter/widgets.dart';
import 'package:mevora/features/location/domain/repositories/location_repository.dart';
import 'package:mevora/features/location/presentation/controllers/location_controller.dart';

/// Injects location use-cases. Widgets never call GPS APIs directly.
class LocationScope extends InheritedWidget {
  const LocationScope({
    super.key,
    required this.repository,
    required this.controller,
    required super.child,
  });

  final LocationRepository repository;
  final LocationController controller;

  static LocationScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocationScope>();
    assert(scope != null, 'LocationScope not found in the widget tree');
    return scope!;
  }

  static LocationScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<LocationScope>();
  }

  @override
  bool updateShouldNotify(LocationScope oldWidget) {
    return repository != oldWidget.repository ||
        controller != oldWidget.controller;
  }
}
