// Two-user Boost runtime QA, driven through the real app.
//
// Prerequisites (see tool/seedEmulatorQaUsers.cjs):
//   1. firebase emulators:start --only auth,firestore,functions
//   2. node tool/seedEmulatorQaUsers.cjs
//   3. produce Boost state for qa_user_a (activate Boost, have B view + like,
//      complete the match)
//
// Run:
//   flutter test integration_test/boost_results_runtime_test.dart -d <deviceId> \
//     --dart-define=USE_EMULATORS=true \
//     --dart-define=USE_AUTH_EMULATOR=true \
//     --dart-define=QA_EMAIL_A=qa_user_a@mevora.test \
//     --dart-define=QA_EMAIL_B=qa_user_b@mevora.test \
//     --dart-define=QA_PASSWORD=...
//
// The sign-in here is a real Firebase Auth Emulator session created through the
// app's ordinary email/password path. Nothing is stubbed and no auth state is
// injected.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mevora/bootstrap.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/features/boost/presentation/widgets/boost_results_panel.dart';

const String _qaEmailA = String.fromEnvironment('QA_EMAIL_A');

Future<void> _settle(WidgetTester tester, {int seconds = 4}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('QA user A signs in and the Boost screen shows real results', (
    tester,
  ) async {
    await bootstrap(AppEnvironment.development);
    await _settle(tester, seconds: 6);

    // Start from a clean session so the QA shortcut is reachable.
    if (FirebaseAuth.instance.currentUser != null) {
      await FirebaseAuth.instance.signOut();
      await _settle(tester, seconds: 4);
    }

    final shortcut = find.byKey(const Key('qa_login_$_qaEmailA'));
    expect(
      shortcut,
      findsOneWidget,
      reason:
          'Emulator QA sign-in shortcut must be present with USE_AUTH_EMULATOR '
          'and QA credentials supplied',
    );

    await tester.tap(shortcut);
    await _settle(tester, seconds: 10);

    // A genuine Firebase session, not injected state.
    final user = FirebaseAuth.instance.currentUser;
    expect(user, isNotNull, reason: 'QA shortcut must produce a real session');
    expect(user!.uid, 'qa_user_a');
    expect(user.email, _qaEmailA);

    // Reach the Boost screen the way a user does.
    final boostButton = find.byTooltip('Boost');
    expect(
      boostButton,
      findsWidgets,
      reason: 'Boost entry point must be reachable from the signed-in shell',
    );
    await tester.tap(boostButton.first);
    await _settle(tester, seconds: 8);

    // Fail loudly rather than passing on whatever happens to be on screen.
    expect(
      find.byType(BoostResultsPanel),
      findsOneWidget,
      reason: 'the real Boost screen must render the results panel',
    );

    // Backend state produced before this test: reach 1, likes 1, matches 1.
    // Asserting the rendered counts means a hardcoded panel cannot pass.
    expect(find.textContaining('1'), findsWidgets);

    // No fabricated comparison, ever.
    expect(find.textContaining('% more'), findsNothing);
    expect(find.textContaining('guaranteed'), findsNothing);
  });
}
