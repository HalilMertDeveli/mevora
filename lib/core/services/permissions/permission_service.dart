import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';

/// Device permission port. Widgets never call OS permission APIs directly.
///
/// Flow: Widget → Controller → [PermissionService] → platform.
abstract class PermissionService {
  Future<PermissionStatus> check(PermissionType type);

  Future<PermissionStatus> request(PermissionType type);

  Future<bool> isPermanentlyDenied(PermissionType type);

  Future<bool> openSettings();

  Future<Map<PermissionType, PermissionStatus>> checkAll();
}
