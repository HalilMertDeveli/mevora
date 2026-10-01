import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/location_scope.dart';
import 'package:mevora/core/di/permission_scope.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/core/testing/fake_permission_service.dart';
import 'package:mevora/features/location/domain/entities/location_flags.dart';
import 'package:mevora/features/location/presentation/controllers/location_controller.dart';
import 'package:mevora/features/permissions/presentation/controllers/permission_controller.dart';
import 'package:mevora/features/settings/presentation/pages/location_settings_page.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

import '../../helpers/pump_app.dart';

const _uid = 'u1';
final _en = lookupAppLocalizations(const Locale('en'));

/// A member who skipped location at the start: the step is done, location is off.
Future<({FakeLocationRepository repository, FakePermissionService service})>
_pumpPage(
  WidgetTester tester, {
  required PermissionStatus permission,
  PermissionStatus? afterRequest,
}) async {
  final repository = FakeLocationRepository()
    ..flags[_uid] = const LocationFlags(
      uid: _uid,
      locationEnabled: false,
      locationOnboardingCompleted: true,
    );
  final location = LocationController(
    repository: repository,
    successHold: Duration.zero,
  );
  addTearDown(location.dispose);
  await location.syncForUser(_uid);
  final service = FakePermissionService(
    statuses: {PermissionType.location: permission},
  );
  if (afterRequest != null) {
    service.requestResults[PermissionType.location] = afterRequest;
  }
  final controller = PermissionController(service: service);
  await tester.pumpWidget(
    wrapWithApp(
      LocationScope(
        repository: repository,
        controller: location,
        child: PermissionScope(
          service: service,
          controller: controller,
          child: const LocationSettingsPage(),
        ),
      ),
      scaffold: false,
    ),
  );
  await tester.pumpAndSettle();
  return (repository: repository, service: service);
}

void main() {
  testWidgets('with the permission already allowed, the button stores the '
      'location and switches it on', (tester) async {
    final page = await _pumpPage(tester, permission: PermissionStatus.granted);

    await tester.tap(find.text(_en.useMyLocation));
    await tester.pumpAndSettle();

    // No second permission prompt for something already granted.
    expect(page.service.requestCalls, isEmpty);
    expect(page.repository.stored[_uid], isNotNull);
    expect(page.repository.flags[_uid]!.locationEnabled, isTrue);
    expect(find.text(_en.locationSuccessTitle), findsOneWidget);
  });

  testWidgets('without the permission, it asks first and then stores the '
      'location', (tester) async {
    final page = await _pumpPage(
      tester,
      permission: PermissionStatus.denied,
      afterRequest: PermissionStatus.granted,
    );

    await tester.tap(find.text(_en.useMyLocation));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.permissionAllow));
    await tester.pumpAndSettle();

    expect(page.service.requestCalls, [PermissionType.location]);
    expect(page.repository.stored[_uid], isNotNull);
    expect(page.repository.flags[_uid]!.locationEnabled, isTrue);
  });

  testWidgets('a refused permission leaves location off', (tester) async {
    final page = await _pumpPage(
      tester,
      permission: PermissionStatus.denied,
      afterRequest: PermissionStatus.denied,
    );

    await tester.tap(find.text(_en.useMyLocation));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.permissionAllow));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.permissionContinueWithout));
    await tester.pumpAndSettle();

    expect(page.repository.captureCalls, 0);
    expect(page.repository.flags[_uid]!.locationEnabled, isFalse);
  });

  testWidgets('a location that cannot be read is reported, not ignored', (
    tester,
  ) async {
    final page = await _pumpPage(tester, permission: PermissionStatus.granted);
    page.repository.captureFailure = const LocationFailure(
      'Location request timed out.',
      kind: LocationErrorKind.timeout,
    );

    await tester.tap(find.text(_en.useMyLocation));
    await tester.pumpAndSettle();

    expect(page.repository.flags[_uid]!.locationEnabled, isFalse);
    expect(find.text(_en.locationSuccessTitle), findsNothing);
    expect(find.text(_en.locationTimeoutMessage), findsOneWidget);
  });

  testWidgets('location settings opens without initState inherited lookup crash', (
    tester,
  ) async {
    final service = FakePermissionService(
      statuses: {PermissionType.location: PermissionStatus.denied},
    );
    final controller = PermissionController(service: service);

    await tester.pumpWidget(
      wrapWithApp(
        PermissionScope(
          service: service,
          controller: controller,
          child: const LocationSettingsPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(LocationSettingsPage), findsOneWidget);
    expect(service.checkCalls, contains(PermissionType.location));
    expect(find.byType(MevoraButton), findsWidgets);
  });
}
