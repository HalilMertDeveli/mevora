import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/permission_scope.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/core/testing/fake_permission_service.dart';
import 'package:mevora/features/permissions/presentation/controllers/permission_controller.dart';
import 'package:mevora/features/settings/presentation/pages/location_settings_page.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

import '../../helpers/pump_app.dart';

void main() {
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
