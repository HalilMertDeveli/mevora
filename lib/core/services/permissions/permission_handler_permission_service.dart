import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'package:mevora/core/services/permissions/permission_service.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';

/// Production [PermissionService] using `permission_handler`.
///
/// Location is while-in-use only (`Permission.locationWhenInUse`).
/// Photos prefer limited/selected access on platforms that support it.
///
/// On Android there is no photo permission to ask for: every gallery flow goes
/// through the system photo picker (`image_picker`), which hands the app only
/// the images the member picked. The manifest therefore declares neither
/// READ_MEDIA_IMAGES nor READ_MEDIA_VISUAL_USER_SELECTED (Google Play's Photo
/// and Video Permissions policy), and asking `permission_handler` for
/// `Permission.photos` would report "denied" for a permission that is not
/// needed. [PermissionType.photos] is reported as granted there instead.
class PermissionHandlerPermissionService implements PermissionService {
  const PermissionHandlerPermissionService();

  @override
  Future<PermissionStatus> check(PermissionType type) async {
    if (needsNoRuntimePermission(type)) {
      return PermissionStatus.granted;
    }
    try {
      return mapHandlerStatus(await _platform(type).status);
    } on Object {
      return PermissionStatus.unknown;
    }
  }

  @override
  Future<PermissionStatus> request(PermissionType type) async {
    if (needsNoRuntimePermission(type)) {
      return PermissionStatus.granted;
    }
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

  /// True when the platform serves [type] without any runtime permission.
  @visibleForTesting
  static bool needsNoRuntimePermission(PermissionType type) {
    return type == PermissionType.photos &&
        defaultTargetPlatform == TargetPlatform.android;
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
