import 'package:mevora/core/services/permissions/permission_service.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';

class FakePermissionService implements PermissionService {
  FakePermissionService({
    Map<PermissionType, PermissionStatus>? statuses,
  }) : statuses = Map<PermissionType, PermissionStatus>.from(
         statuses ??
             {
               for (final type in PermissionType.values)
                 type: PermissionStatus.denied,
             },
       );

  final Map<PermissionType, PermissionStatus> statuses;
  final Map<PermissionType, PermissionStatus> requestResults = {};
  final List<PermissionType> checkCalls = [];
  final List<PermissionType> requestCalls = [];
  bool settingsOpened = false;
  Object? throwOnRequest;
  Object? throwOnCheck;

  @override
  Future<PermissionStatus> check(PermissionType type) async {
    checkCalls.add(type);
    final error = throwOnCheck;
    if (error != null) {
      throw error;
    }
    return statuses[type] ?? PermissionStatus.unknown;
  }

  @override
  Future<PermissionStatus> request(PermissionType type) async {
    requestCalls.add(type);
    final error = throwOnRequest;
    if (error != null) {
      throw error;
    }
    final next = requestResults[type] ?? statuses[type] ?? PermissionStatus.denied;
    statuses[type] = next;
    return next;
  }

  @override
  Future<bool> isPermanentlyDenied(PermissionType type) async {
    final status = await check(type);
    return status.isPermanentlyDenied;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened = true;
    return true;
  }

  @override
  Future<Map<PermissionType, PermissionStatus>> checkAll() async {
    final result = <PermissionType, PermissionStatus>{};
    for (final type in PermissionType.values) {
      result[type] = await check(type);
    }
    return result;
  }
}
