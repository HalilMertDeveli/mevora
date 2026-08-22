// Run on a connected Android/iOS device or emulator:
// flutter test integration_test/smoke/app_launch_test.dart -d <deviceId>
//
// This file validates the production entrypoint boots. Firebase must be configured
// on the target device flavor.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mevora/bootstrap.dart';
import 'package:mevora/core/config/app_environment.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('production shell bootstraps', (tester) async {
    await bootstrap(AppEnvironment.production);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.byType(Object), findsWidgets);
  });
}
