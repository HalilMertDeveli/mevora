import 'package:mevora/core/services/permissions/permission_handler_permission_service.dart';
import 'package:mevora/core/services/permissions/permission_service.dart';
import 'package:mevora/features/permissions/presentation/controllers/permission_controller.dart';

class PermissionServices {
  const PermissionServices({
    required this.service,
    required this.controller,
  });

  final PermissionService service;
  final PermissionController controller;
}

PermissionServices createPermissionServices({
  PermissionService? service,
  Future<void> Function()? onNotificationsGranted,
}) {
  final resolved = service ?? const PermissionHandlerPermissionService();
  return PermissionServices(
    service: resolved,
    controller: PermissionController(
      service: resolved,
      onNotificationsGranted: onNotificationsGranted,
    ),
  );
}
