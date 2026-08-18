import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/core/testing/fake_permission_service.dart';
import 'package:mevora/features/permissions/presentation/controllers/permission_controller.dart';

void main() {
  late FakePermissionService service;
  late PermissionController controller;

  setUp(() {
    service = FakePermissionService();
    controller = PermissionController(service: service);
  });

  tearDown(() {
    controller.dispose();
  });

  for (final type in PermissionType.values) {
    group('$type', () {
      test('granted', () async {
        service.statuses[type] = PermissionStatus.granted;
        expect(await controller.check(type), PermissionStatus.granted);
        expect(await controller.request(type), PermissionStatus.granted);
      });

      test('denied', () async {
        service.statuses[type] = PermissionStatus.denied;
        service.requestResults[type] = PermissionStatus.denied;
        expect(await controller.check(type), PermissionStatus.denied);
        expect(await controller.request(type), PermissionStatus.denied);
      });

      test('permanentlyDenied', () async {
        service.statuses[type] = PermissionStatus.permanentlyDenied;
        expect(await controller.isPermanentlyDenied(type), isTrue);
        expect(
          await controller.request(type),
          PermissionStatus.permanentlyDenied,
        );
        expect(service.requestCalls, isEmpty);
      });

      test('limited is usable', () async {
        service.statuses[type] = PermissionStatus.limited;
        final status = await controller.check(type);
        expect(status, PermissionStatus.limited);
        expect(status.isUsable, isTrue);
      });
    });
  }

  test('checkAll does not request', () async {
    await controller.checkAll();
    expect(service.requestCalls, isEmpty);
    expect(service.checkCalls, PermissionType.values);
  });

  test('request failure becomes unknown and does not crash', () async {
    service.throwOnRequest = Exception('platform');
    service.statuses[PermissionType.camera] = PermissionStatus.denied;
    expect(
      await controller.request(PermissionType.camera),
      PermissionStatus.unknown,
    );
  });

  test('notifications callback runs only when granted', () async {
    var grantedCalls = 0;
    final notifying = PermissionController(
      service: service,
      onNotificationsGranted: () async {
        grantedCalls += 1;
      },
    );
    addTearDown(notifying.dispose);
    service.statuses[PermissionType.notifications] = PermissionStatus.denied;
    service.requestResults[PermissionType.notifications] =
        PermissionStatus.granted;
    await notifying.request(PermissionType.notifications);
    expect(grantedCalls, 1);

    service.requestResults[PermissionType.camera] = PermissionStatus.granted;
    await notifying.request(PermissionType.camera);
    expect(grantedCalls, 1);
  });
}
