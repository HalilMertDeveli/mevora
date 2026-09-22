// Two-device ghost-user acceptance — DEVICE A side.
//
// Deletes QA User A through the real application UI:
//   Settings -> Delete account -> Account settings -> Delete account -> confirm
// No Admin SDK substitute; this exercises the user-facing path end to end.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mevora/core/config/app_environment.dart';

import 'ghost_helpers.dart';

const _emailA = String.fromEnvironment('QA_A_EMAIL');
const _password = String.fromEnvironment('QA_E2E_PASSWORD');

Future<bool> _tapFirstText(WidgetTester tester, List<String> labels,
    {Duration settle = const Duration(seconds: 4), bool scroll = true}) async {
  for (final label in labels) {
    var f = find.text(label);
    if (f.evaluate().isEmpty && scroll) {
      // Settings is a long scrollable list; the destructive tile is below the fold.
      final scrollable = find.byType(Scrollable);
      for (var i = 0; i < 12 && f.evaluate().isEmpty; i++) {
        if (scrollable.evaluate().isEmpty) break;
        await tester.drag(scrollable.first, const Offset(0, -320));
        await pumpFor(tester, const Duration(milliseconds: 600));
        f = find.text(label);
      }
    }
    if (f.evaluate().isNotEmpty) {
      debugPrint('[QA] tap "$label"');
      await tester.tap(f.last, warnIfMissed: false);
      await pumpFor(tester, settle);
      return true;
    }
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('delete_account_a', (tester) async {
    if (_emailA.isEmpty || _password.isEmpty) {
      fail('Missing --dart-define QA_A_EMAIL / QA_E2E_PASSWORD');
    }

    await bootstrapForTest(AppEnvironment.development);
    await pumpFor(tester, const Duration(seconds: 3));

    await signIn(tester, email: _emailA, password: _password);
    await waitForShell(tester);
    await dismissBlockers(tester);
    final uidBefore = FirebaseAuth.instance.currentUser?.uid;
    expect(uidBefore, isNotNull);
    debugPrint('[QA] A_SIGNED_IN uid=$uidBefore');

    // There is no Settings tab: Settings opens from the Profile tab's gear icon.
    final profileTab = await openTab(tester, ['Profile', 'Profil']);
    expect(profileTab, isTrue, reason: 'Profile tab not reachable');
    await pumpFor(tester, const Duration(seconds: 4));

    final gear = find.byIcon(Icons.settings_outlined);
    expect(gear.evaluate(), isNotEmpty,
        reason: 'Settings entry point not found visible=${visibleTexts(tester)}');
    await tester.tap(gear.first, warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 5));
    debugPrint('[QA] SETTINGS_OPEN visible=${visibleTexts(tester)}');

    // Settings -> "Delete account" nav tile (routes to Account settings).
    var opened = await _tapFirstText(tester, ['Delete account', 'Hesabı sil']);
    if (!opened) {
      // Some builds surface it only under Account settings / Linked accounts.
      await _tapFirstText(tester, ['Account settings', 'Hesap ayarları',
        'Linked accounts', 'Bağlı hesaplar']);
      opened = await _tapFirstText(tester, ['Delete account', 'Hesabı sil']);
    }
    expect(opened, isTrue,
        reason: 'Delete account entry point not found visible=${visibleTexts(tester)}');

    // Account settings page -> destructive Delete account button.
    await _tapFirstText(tester, ['Delete account', 'Hesabı sil']);
    await pumpFor(tester, const Duration(seconds: 3));

    // Confirmation dialog must exist — an accidental tap must not delete.
    final dialogUp = await waitUntil(
      tester,
      () => anyTextContains('Delete your account?') ||
          anyTextContains('Hesabın silinsin mi?') ||
          anyTextContains('Delete forever') ||
          anyTextContains('Kalıcı olarak sil'),
      timeout: const Duration(seconds: 30),
    );
    expect(dialogUp, isTrue,
        reason: 'no deletion confirmation shown visible=${visibleTexts(tester)}');
    debugPrint('[QA] CONFIRM_DIALOG_OK visible=${visibleTexts(tester)}');

    final confirmed = await _tapFirstText(
      tester, ['Delete forever', 'Kalıcı olarak sil'],
      settle: const Duration(seconds: 10));
    expect(confirmed, isTrue,
        reason: 'confirm button not found visible=${visibleTexts(tester)}');
    debugPrint('[QA] DELETE_CONFIRMED');

    // The deletion callable runs server-side; wait for the session to drop.
    final signedOut = await waitUntil(
      tester,
      () => FirebaseAuth.instance.currentUser == null,
      timeout: const Duration(minutes: 5),
    );
    expect(signedOut, isTrue,
        reason: 'A remained authenticated after deletion visible=${visibleTexts(tester)}');
    debugPrint('[QA] A_SIGNED_OUT');

    // And the app must land somewhere unauthenticated, not a stale home screen.
    await pumpFor(tester, const Duration(seconds: 8));
    final onAuthScreen = anyTextContains('Sign in') || anyTextContains('Giriş') ||
        anyTextContains('Log in') || anyTextContains('Welcome') ||
        anyTextContains('Hoş geldin') || anyTextContains('E-posta') ||
        anyTextContains('Email');
    debugPrint('[QA] POST_DELETE_SCREEN onAuth=$onAuthScreen visible=${visibleTexts(tester)}');
    expect(
      find.text('Keşfet').evaluate().isEmpty && find.text('Discover').evaluate().isEmpty,
      isTrue,
      reason: 'authenticated shell still showing after deletion',
    );
    debugPrint('[QA] A_DELETION_OK');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
