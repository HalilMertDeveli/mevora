// Run on a connected device or emulator:
// flutter test integration_test/readme_screenshots_test.dart -d emulator-5554
//
// Saves PNG files under screenshots/ (copied to docs/images/ by tools/screenshots/copy_screenshots.ps1).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mevora/bootstrap.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/l10n/app_localizations.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture README screenshots from the running app', (tester) async {
    await bootstrap(AppEnvironment.development);
    await tester.pumpAndSettle(const Duration(seconds: 4));

    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.textContaining('Mevora', findRichText: true), findsWidgets);

    await binding.takeScreenshot('mevora-login');

    final createAccount = find.text(l10n.createAccount);
    if (createAccount.evaluate().isNotEmpty) {
      await tester.ensureVisible(createAccount);
      await tester.tap(createAccount);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await binding.takeScreenshot('mevora-register');
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    final emailEntry = find.text(l10n.continueWithEmail);
    if (emailEntry.evaluate().isNotEmpty) {
      await tester.ensureVisible(emailEntry);
      await tester.tap(emailEntry);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await binding.takeScreenshot('mevora-login-email');
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    await binding.takeScreenshot('mevora-hero');
  });
}
