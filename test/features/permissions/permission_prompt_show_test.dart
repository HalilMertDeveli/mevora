import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/permission_scope.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/core/testing/fake_permission_service.dart';
import 'package:mevora/features/permissions/domain/permission_flow_outcome.dart';
import 'package:mevora/features/permissions/presentation/controllers/permission_controller.dart';
import 'package:mevora/features/permissions/presentation/pages/permission_prompt_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/pump_app.dart';

/// `PermissionPromptPage.show` is what every feature calls before it uses the
/// camera, the gallery, the microphone or notifications. The pre-prompt is
/// for a request that is about to be made — not for one already settled.
void main() {
  late FakePermissionService service;
  late PermissionController controller;
  final l10n = lookupAppLocalizations(const Locale('en'));
  PermissionFlowOutcome? outcome;

  setUp(() {
    service = FakePermissionService(
      statuses: {
        for (final type in PermissionType.values) type: PermissionStatus.denied,
      },
    );
    controller = PermissionController(service: service);
    outcome = null;
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpAndOpen(WidgetTester tester, PermissionType type) async {
    await tester.pumpWidget(
      PermissionScope(
        service: service,
        controller: controller,
        child: wrapWithApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                outcome = await PermissionPromptPage.show(context, type: type);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('an already granted permission shows no pre-prompt', (
    tester,
  ) async {
    service.statuses[PermissionType.camera] = PermissionStatus.granted;

    await pumpAndOpen(tester, PermissionType.camera);

    expect(find.text(l10n.permissionCameraDescription), findsNothing);
    expect(outcome, PermissionFlowOutcome.granted);
    expect(service.requestCalls, isEmpty);
  });

  testWidgets('limited access is reported as limited, without a pre-prompt', (
    tester,
  ) async {
    service.statuses[PermissionType.photos] = PermissionStatus.limited;

    await pumpAndOpen(tester, PermissionType.photos);

    expect(find.text(l10n.permissionPhotosDescription), findsNothing);
    expect(outcome, PermissionFlowOutcome.limited);
    expect(service.requestCalls, isEmpty);
  });

  testWidgets('a permission not yet granted is still explained first', (
    tester,
  ) async {
    await pumpAndOpen(tester, PermissionType.microphone);

    expect(find.text(l10n.permissionMicrophoneDescription), findsOneWidget);
    expect(outcome, isNull);
    expect(service.requestCalls, isEmpty);

    service.requestResults[PermissionType.microphone] =
        PermissionStatus.granted;
    await tester.tap(find.text(l10n.permissionAllow));
    await tester.pumpAndSettle();

    expect(service.requestCalls, [PermissionType.microphone]);
    expect(outcome, PermissionFlowOutcome.granted);
  });

  testWidgets('a permanently denied permission still opens the page', (
    tester,
  ) async {
    service.statuses[PermissionType.location] =
        PermissionStatus.permanentlyDenied;

    await pumpAndOpen(tester, PermissionType.location);

    expect(find.text(l10n.permissionLocationDescription), findsOneWidget);
    expect(outcome, isNull);
  });
}
