// Run on a connected Android/iOS device or emulator:
// flutter test integration_test/smoke/app_launch_test.dart -d <deviceId> --flavor development
//
// Validates the development entrypoint boots to a non-empty widget tree.
// Use AppEnvironment.development with the development flavor so Firebase options match.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mevora/bootstrap.dart';
import 'package:mevora/core/config/app_environment.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('development shell bootstraps', (tester) async {
    await bootstrap(AppEnvironment.development);
    // Allow async Firebase / router init without requiring a fully settled tree
    // (animations / network may keep the scheduler busy).
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(MaterialApp), findsWidgets);
  });
}
