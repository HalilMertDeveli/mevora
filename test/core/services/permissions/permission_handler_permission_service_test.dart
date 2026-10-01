import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/services/permissions/permission_handler_permission_service.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';

/// The Android manifest declares no photo permission: gallery picks use the
/// system photo picker. The service must therefore never ask the platform for
/// one there — it would come back "denied" and block the picker.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = PermissionHandlerPermissionService();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android reports photos as granted without a platform call', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    // No permission_handler channel is registered in this test. A platform
    // call would fail and surface as unknown, so granted proves there was none.
    expect(
      await service.check(PermissionType.photos),
      PermissionStatus.granted,
    );
    expect(
      await service.request(PermissionType.photos),
      PermissionStatus.granted,
    );
    expect(await service.isPermanentlyDenied(PermissionType.photos), isFalse);
  });

  test('Android still asks the platform for every other permission', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    for (final type in PermissionType.values) {
      expect(
        PermissionHandlerPermissionService.needsNoRuntimePermission(type),
        type == PermissionType.photos,
        reason: '$type',
      );
    }
  });

  test('iOS keeps asking for photo access', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    expect(
      PermissionHandlerPermissionService.needsNoRuntimePermission(
        PermissionType.photos,
      ),
      isFalse,
    );
    // The missing channel turns the real request into unknown, not granted.
    expect(
      await service.check(PermissionType.photos),
      PermissionStatus.unknown,
    );
  });
}
