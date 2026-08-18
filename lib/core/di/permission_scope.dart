import 'package:flutter/widgets.dart';
import 'package:mevora/core/services/permissions/permission_service.dart';
import 'package:mevora/features/permissions/presentation/controllers/permission_controller.dart';

/// Injects [PermissionService]. Widgets never call OS permission APIs.
class PermissionScope extends InheritedWidget {
  const PermissionScope({
    super.key,
    required this.service,
    required this.controller,
    required super.child,
  });

  final PermissionService service;
  final PermissionController controller;

  static PermissionScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PermissionScope>();
    assert(scope != null, 'PermissionScope not found in the widget tree');
    return scope!;
  }

  static PermissionScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<PermissionScope>();
  }

  @override
  bool updateShouldNotify(PermissionScope oldWidget) {
    return service != oldWidget.service || controller != oldWidget.controller;
  }
}
