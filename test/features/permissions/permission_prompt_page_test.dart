import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/permission_scope.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/core/testing/fake_permission_service.dart';
import 'package:mevora/features/permissions/presentation/controllers/permission_controller.dart';
import 'package:mevora/features/permissions/presentation/pages/permission_prompt_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/pump_app.dart';

Widget _wrap(
  Widget child, {
  required FakePermissionService service,
  required PermissionController controller,
}) {
  return PermissionScope(
    service: service,
    controller: controller,
    child: wrapWithApp(child, scaffold: false),
  );
}

void main() {
  late FakePermissionService service;
  late PermissionController controller;
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUp(() {
    service = FakePermissionService();
    controller = PermissionController(service: service);
  });

  tearDown(() {
    controller.dispose();
  });

  testWidgets('explains before requesting and does not request on load', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const PermissionPromptPage(type: PermissionType.camera),
        service: service,
        controller: controller,
      ),
    );
    await tester.pump();

    expect(find.text(l10n.permissionCameraTitle), findsOneWidget);
    expect(find.text(l10n.permissionCameraDescription), findsOneWidget);
    expect(service.requestCalls, isEmpty);

    service.requestResults[PermissionType.camera] = PermissionStatus.granted;
    await tester.tap(find.text(l10n.permissionAllow));
    await tester.pump();
    await tester.pump();

    expect(service.requestCalls, [PermissionType.camera]);
  });

  testWidgets('denied offers try again and continue without crashing', (
    tester,
  ) async {
    service.statuses[PermissionType.photos] = PermissionStatus.denied;
    service.requestResults[PermissionType.photos] = PermissionStatus.denied;

    await tester.pumpWidget(
      _wrap(
        const PermissionPromptPage(type: PermissionType.photos),
        service: service,
        controller: controller,
      ),
    );
    await tester.tap(find.text(l10n.permissionAllow));
    await tester.pump();
    await tester.pump();

    expect(find.text(l10n.permissionDeniedTitle), findsOneWidget);
    expect(find.text(l10n.tryAgain), findsOneWidget);
    expect(find.text(l10n.permissionContinueWithout), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permanently denied offers open settings', (tester) async {
    service.statuses[PermissionType.location] =
        PermissionStatus.permanentlyDenied;

    await tester.pumpWidget(
      _wrap(
        const PermissionPromptPage(type: PermissionType.location),
        service: service,
        controller: controller,
      ),
    );
    await tester.tap(find.text(l10n.permissionAllow));
    await tester.pump();
    await tester.pump();

    expect(find.text(l10n.openSettings), findsOneWidget);
    await tester.tap(find.text(l10n.openSettings));
    await tester.pump();
    expect(service.settingsOpened, isTrue);
  });
}
