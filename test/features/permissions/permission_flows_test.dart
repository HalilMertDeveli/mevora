import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/permission_scope.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/core/testing/fake_permission_service.dart';
import 'package:mevora/features/permissions/presentation/controllers/permission_controller.dart';
import 'package:mevora/features/permissions/presentation/pages/add_photo_permission_page.dart';
import 'package:mevora/features/permissions/presentation/pages/privacy_permissions_page.dart';
import 'package:mevora/features/permissions/presentation/widgets/notification_permission_gate.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/pump_app.dart';

void main() {
  late FakePermissionService service;
  late PermissionController controller;
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUp(() {
    service = FakePermissionService(
      statuses: {
        for (final type in PermissionType.values)
          type: PermissionStatus.denied,
      },
    );
    controller = PermissionController(service: service);
  });

  tearDown(() {
    controller.dispose();
  });

  Widget wrap(Widget child) {
    return PermissionScope(
      service: service,
      controller: controller,
      child: wrapWithApp(child, scaffold: false),
    );
  }

  testWidgets('privacy page lists all permissions and does not request', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const PrivacyPermissionsPage()));
    await tester.pump();
    await tester.pump();

    expect(find.text(l10n.privacyPermissionsTitle), findsWidgets);
    expect(find.text(l10n.permissionCameraTitle), findsOneWidget);
    expect(find.text(l10n.permissionMicrophoneTitle), findsOneWidget);
    expect(find.text(l10n.permissionPhotosTitle), findsOneWidget);
    expect(find.text(l10n.permissionLocationTitle), findsOneWidget);
    expect(find.text(l10n.permissionNotificationsTitle), findsOneWidget);
    expect(find.text(l10n.privacyOpenDeviceSettings), findsOneWidget);
    expect(service.requestCalls, isEmpty);
  });

  testWidgets('add photo camera and gallery do not crash when denied', (
    tester,
  ) async {
    service.requestResults[PermissionType.camera] = PermissionStatus.denied;
    service.requestResults[PermissionType.photos] = PermissionStatus.limited;

    await tester.pumpWidget(wrap(const AddPhotoPermissionPage()));
    await tester.pump();

    await tester.tap(find.byKey(const Key('add_photo_camera')));
    await tester.pump();
    await tester.pump();
    expect(find.text(l10n.permissionCameraDescription), findsOneWidget);
    await tester.tap(find.text(l10n.permissionContinueWithout).first);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('add_photo_gallery')));
    await tester.pump();
    await tester.pump();
    expect(find.text(l10n.permissionPhotosDescription), findsOneWidget);
    await tester.tap(find.text(l10n.permissionAllow));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('add_photo_outcome')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification gate checks but does not request on open', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const Scaffold(body: NotificationPermissionGate())),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('enable_notifications')), findsOneWidget);
    expect(service.requestCalls, isEmpty);
    expect(service.checkCalls, contains(PermissionType.notifications));
  });
}
