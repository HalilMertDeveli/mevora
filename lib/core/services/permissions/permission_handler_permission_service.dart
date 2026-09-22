import 'package:permission_handler/permission_handler.dart' as ph;

import 'package:mevora/core/services/permissions/permission_service.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';

/// Production [PermissionService] using `permission_handler`.
///
/// Location is while-in-use only (`Permission.locationWhenInUse`).
/// Photos prefer limited/selected access on platforms that support it.
class PermissionHandlerPermissionService implements PermissionService {
  const PermissionHandlerPermissionService();

  @override
  Future<PermissionStatus> check(PermissionType type) async {
    try {
      return mapHandlerStatus(await _platform(type).status);
    } on Object {
      return PermissionStatus.unknown;
    }
  }

  @override
  Future<PermissionStatus> request(PermissionType type) async {
    try {
      final permission = _platform(type);
      final current = mapHandlerStatus(await permission.status);
      if (current.isPermanentlyDenied) {
        return current;
      }
      return mapHandlerStatus(await permission.request());
    } on Object {
      return PermissionStatus.unknown;
    }
  }

  @override
  Future<bool> isPermanentlyDenied(PermissionType type) async {
    final status = await check(type);
    return status.isPermanentlyDenied;
  }

  @override
  Future<bool> openSettings() async {
    try {
      return await ph.openAppSettings();
    } on Object {
      return false;
    }
  }

  @override
  Future<Map<PermissionType, PermissionStatus>> checkAll() async {
    final entries = <PermissionType, PermissionStatus>{};
    for (final type in PermissionType.values) {
      entries[type] = await check(type);
    }
    return entries;
  }

  ph.Permission _platform(PermissionType type) {
    return switch (type) {
      PermissionType.camera => ph.Permission.camera,
      PermissionType.microphone => ph.Permission.microphone,
      PermissionType.photos => ph.Permission.photos,
      PermissionType.notifications => ph.Permission.notification,
      PermissionType.location => ph.Permission.locationWhenInUse,
    };
  }
}

PermissionStatus mapHandlerStatus(ph.PermissionStatus status) {
  return switch (status) {
    ph.PermissionStatus.granted => PermissionStatus.granted,
    ph.PermissionStatus.denied => PermissionStatus.denied,
    ph.PermissionStatus.restricted => PermissionStatus.restricted,
    ph.PermissionStatus.limited => PermissionStatus.limited,
    ph.PermissionStatus.permanentlyDenied => PermissionStatus.permanentlyDenied,
    ph.PermissionStatus.provisional => PermissionStatus.granted,
  };
}
