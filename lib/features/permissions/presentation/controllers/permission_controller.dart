import 'package:flutter/foundation.dart';
import 'package:mevora/core/services/permissions/permission_service.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';

/// Presentation controller for device permissions.
///
/// Never requests every permission at once. Call [request] only when a
/// feature actually needs that permission.
class PermissionController extends ChangeNotifier {
  PermissionController({
    required PermissionService service,
    this.onNotificationsGranted,
  }) : _service = service;

  final PermissionService _service;
  final Future<void> Function()? onNotificationsGranted;

  final Map<PermissionType, PermissionStatus> statuses = {
    for (final type in PermissionType.values) type: PermissionStatus.unknown,
  };

  bool isBusy = false;
  PermissionType? activeType;

  Future<PermissionStatus> check(PermissionType type) async {
    final status = await _service.check(type);
    statuses[type] = status;
    notifyListeners();
    return status;
  }

  Future<PermissionStatus> request(PermissionType type) async {
    if (isBusy) {
      return statuses[type] ?? PermissionStatus.unknown;
    }
    isBusy = true;
    activeType = type;
    notifyListeners();
    try {
      var status = await _service.check(type);
      if (status.isPermanentlyDenied) {
        statuses[type] = status;
        return status;
      }
      status = await _service.request(type);
      statuses[type] = status;
      if (type == PermissionType.notifications && status.isUsable) {
        await onNotificationsGranted?.call();
      }
      return status;
    } on Object {
      statuses[type] = PermissionStatus.unknown;
      return PermissionStatus.unknown;
    } finally {
      isBusy = false;
      activeType = null;
      notifyListeners();
    }
  }

  Future<bool> isPermanentlyDenied(PermissionType type) {
    return _service.isPermanentlyDenied(type);
  }

  Future<bool> openSettings() => _service.openSettings();

  Future<Map<PermissionType, PermissionStatus>> checkAll() async {
    final next = await _service.checkAll();
    statuses
      ..clear()
      ..addAll(next);
    notifyListeners();
    return Map<PermissionType, PermissionStatus>.from(statuses);
  }
}
