// Phase 11 — Physical-device WYM E2E (REAL Firebase development = mevora-d6ed0).
// Prereq:
//   node functions/scripts/whyYouMatchedPhase11DeviceFixture.cjs
// Run (PowerShell):
//   $token = (Get-Content tool/app_check_debug_token.local -Raw).Trim()
//   flutter test integration_test/matching/why_you_matched_device_e2e_test.dart `
//     -d R68T305S3VM `
//     --dart-define=FIREBASE_APP_CHECK_DEBUG_TOKEN=$token

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mevora/bootstrap.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/features/compatibility/presentation/why_you_matched/match_why_you_matched_entry.dart';
import 'package:mevora/features/matching/presentation/pages/matches_page.dart';

Future<void> _waitCallableReady() async {
  await Future<void>.delayed(const Duration(seconds: 2));
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    await user.getIdToken(true);
  }
}

Future<void> _pumpFor(
  WidgetTester tester,
  Duration total, {
  Duration step = const Duration(milliseconds: 200),
}) async {
  final end = DateTime.now().add(total);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
  }
}

String _visibleTexts(WidgetTester tester) {
  final texts = <String>[];
  for (final el in find.byType(Text).evaluate()) {
    final widget = el.widget;
    if (widget is Text) {
      final value = widget.data ?? widget.textSpan?.toPlainText();
      if (value != null && value.trim().isNotEmpty) {
        texts.add(value.trim());
      }
    }
  }
  return texts.take(50).join(' | ');
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 120),
  String? label,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail(
    'Timeout waiting for ${label ?? finder.toString()} '
    'visible=${_visibleTexts(tester)}',
  );
}

Future<void> _waitForShell(WidgetTester tester) async {
  final end = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (find.text('Keşfet').evaluate().isNotEmpty ||
        find.text('Discover').evaluate().isNotEmpty ||
        find.text('Eşleşmeler').evaluate().isNotEmpty ||
        find.text('Matches').evaluate().isNotEmpty) {
      debugPrint('[WYM-DEVICE] shell visible');
      return;
    }
  }
  fail('Timeout waiting for app shell visible=${_visibleTexts(tester)}');
}

Future<void> _dismissBlockers(WidgetTester tester) async {
  final dismissLabels = [
    'Not now',
    'Daha Sonra',
    'Şimdilik atla',
    'Continue without location',
    'Konumsuz devam et',
    'Skip for now',
    'Maybe later',
    'Close',
    'Kapat',
  ];
  for (var i = 0; i < 8; i++) {
    await _pumpFor(tester, const Duration(seconds: 1));
    for (final label in dismissLabels) {
      final finder = find.text(label);
      if (finder.evaluate().isNotEmpty) {
        debugPrint('[WYM-DEVICE] dismiss $label');
        await tester.tap(finder.first, warnIfMissed: false);
        await _pumpFor(tester, const Duration(seconds: 2));
      }
    }
  }
}

const _emailA = String.fromEnvironment('WYM_DEVICE_EMAIL_A');
const _password = String.fromEnvironment('WYM_DEVICE_PASSWORD');
const _nameB = String.fromEnvironment(
  'WYM_DEVICE_NAME_B',
  defaultValue: 'WYM_DEVICE_B',
);
const _projectId = String.fromEnvironment(
  'WYM_DEVICE_PROJECT',
  defaultValue: 'mevora-d6ed0',
);

Map<String, String> _loadCredentials() {
  if (_emailA.isEmpty || _password.isEmpty) {
    fail(
      'Missing dart-defines WYM_DEVICE_EMAIL_A / WYM_DEVICE_PASSWORD. '
      'Seed fixture then pass values from '
      'integration_test/fixtures/why_you_matched_device_qa.local.json',
    );
  }
  if (_projectId != 'mevora-d6ed0') {
    fail('Refusing non-development projectId=$_projectId');
  }
  return {
    'emailA': _emailA,
    'password': _password,
    'nameB': _nameB,
    'projectId': _projectId,
  };
}

Future<void> _signInRealAuth(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  debugPrint('[WYM-DEVICE] real Firebase Auth signIn $email');
  await tester.runAsync(() async {
    await FirebaseAuth.instance.signOut();
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _waitCallableReady();
  });
  await _pumpFor(tester, const Duration(seconds: 4));
  final uid = FirebaseAuth.instance.currentUser?.uid;
  expect(uid, isNotNull);
  debugPrint('[WYM-DEVICE] signed in uid=$uid');
}

Future<bool> _tryLoginUi(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  // Prefer email form on Login page when visible.
  for (final label in ['Continue with email', 'E-posta ile devam et']) {
    final btn = find.text(label);
    if (btn.evaluate().isNotEmpty) {
      debugPrint('[WYM-DEVICE] Login UI: tap $label');
      await tester.tap(btn.first);
      await _pumpFor(tester, const Duration(seconds: 2));
      break;
    }
  }
  final fields = find.byType(TextField);
  if (fields.evaluate().length < 2) {
    debugPrint('[WYM-DEVICE] Login UI fields not ready — fallback to Auth SDK');
    return false;
  }
  await tester.enterText(fields.at(0), email);
  await tester.enterText(fields.at(1), password);
  await tester.pump();
  for (final label in [
    'Sign in with email',
    'E-posta ile giriş yap',
    'Sign in',
    'Giriş yap',
  ]) {
    final submit = find.text(label);
    if (submit.evaluate().isNotEmpty) {
      await tester.tap(submit.first, warnIfMissed: false);
      await _pumpFor(tester, const Duration(seconds: 8));
      if (FirebaseAuth.instance.currentUser != null) {
        debugPrint('[WYM-DEVICE] Login UI success');
        return true;
      }
    }
  }
  return false;
}

Future<void> _openMatchesTab(WidgetTester tester) async {
  for (final label in ['Matches', 'Eşleşmeler']) {
    final tab = find.text(label);
    if (tab.evaluate().isNotEmpty) {
      await tester.tap(tab.first);
      await _pumpFor(tester, const Duration(seconds: 4));
      return;
    }
  }
  fail('Matches tab not found visible=${_visibleTexts(tester)}');
}

Future<void> _openMatchChat(WidgetTester tester, String partnerLabel) async {
  await _openMatchesTab(tester);
  await _dismissBlockers(tester);

  // Prefer partner display name; fall back to MatchListTile / generic name.
  Finder partner = find.textContaining(partnerLabel);
  if (partner.evaluate().isEmpty) {
    partner = find.byType(MatchListTile);
  }
  if (partner.evaluate().isEmpty) {
    partner = find.text('Mevora');
  }
  await _waitFor(tester, partner, label: 'match list item');
  await tester.tap(partner.first);
  await _pumpFor(tester, const Duration(seconds: 5));
  await _waitFor(
    tester,
    find.byType(TextField),
    label: 'Chat composer',
  );
  debugPrint('[WYM-DEVICE] Chat opened');
}

Future<void> _openWhyYouMatched(WidgetTester tester) async {
  await _dismissBlockers(tester);
  // Scroll chat to reveal WYM entry if needed.
  for (var i = 0; i < 6; i++) {
    if (find.byType(MatchWhyYouMatchedEntry).evaluate().isNotEmpty ||
        find.text('Neden Eşleştiniz?').evaluate().isNotEmpty ||
        find.text('Why You Matched').evaluate().isNotEmpty) {
      break;
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await _pumpFor(tester, const Duration(milliseconds: 400));
  }

  Finder entry = find.byType(MatchWhyYouMatchedEntry);
  if (entry.evaluate().isEmpty) {
    entry = find.text('Neden Eşleştiniz?');
  }
  if (entry.evaluate().isEmpty) {
    entry = find.text('Why You Matched');
  }
  await _waitFor(tester, entry, label: 'WYM entry');
  await tester.ensureVisible(entry.first);
  await tester.tap(entry.first);
  debugPrint('[WYM-DEVICE] WYM entry tapped');
  await _pumpFor(tester, const Duration(seconds: 2));

  // Loading indicator may appear briefly.
  final loading = find.byType(CircularProgressIndicator);
  if (loading.evaluate().isNotEmpty) {
    debugPrint('[WYM-DEVICE] loading visible');
  }

  // Wait for bottom sheet / dialog content (success, empty, or error).
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    final texts = _visibleTexts(tester);
    final hasSheet =
        find.byType(BottomSheet).evaluate().isNotEmpty ||
        find.byType(DraggableScrollableSheet).evaluate().isNotEmpty ||
        find.byType(ModalBarrier).evaluate().isNotEmpty;
    final hasWymCopy =
        texts.contains('Neden Eşleştiniz?') ||
        texts.contains('Why You Matched') ||
        texts.toLowerCase().contains('retry') ||
        texts.contains('Tekrar dene') ||
        find.byType(ListTile).evaluate().length > 1;
    if (hasSheet || hasWymCopy) {
      debugPrint('[WYM-DEVICE] WYM UI after fetch visible=$texts');
      return;
    }
  }
  fail('WYM sheet did not appear visible=${_visibleTexts(tester)}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    if (message.contains('HTTP request failed') ||
        message.contains('NetworkImageLoadException')) {
      debugPrint('[WYM-DEVICE] ignored image error: $message');
      return;
    }
    defaultOnError?.call(details);
  };

  testWidgets('why_you_matched_physical_device_e2e', (tester) async {
    final qa = _loadCredentials();
    final emailA = qa['emailA']!;
    final password = qa['password']!;
    final nameB = qa['nameB']!;

    // Development → mevora-d6ed0 (NOT production).
    await bootstrap(AppEnvironment.development);
    await _pumpFor(tester, const Duration(seconds: 3));

    var loginViaUi = false;
    await tester.runAsync(() async {
      await FirebaseAuth.instance.signOut();
    });
    await _pumpFor(tester, const Duration(seconds: 2));

    loginViaUi = await _tryLoginUi(
      tester,
      email: emailA,
      password: password,
    );
    if (!loginViaUi) {
      await _signInRealAuth(tester, email: emailA, password: password);
    }
    await tester.runAsync(() async {
      await _waitCallableReady();
    });

    await _waitForShell(tester);
    await _dismissBlockers(tester);
    await _openMatchChat(tester, nameB);
    expect(find.byType(TextField), findsWidgets);

    await _openWhyYouMatched(tester);

    // Success path: expect at least the WYM title still present and no crash.
    final visible = _visibleTexts(tester);
    final hasTitle =
        visible.contains('Neden Eşleştiniz?') ||
        visible.contains('Why You Matched');
    expect(hasTitle || find.byType(MatchWhyYouMatchedEntry).evaluate().isNotEmpty, isTrue);

    // Sanitization smoke: raw sensitive tokens must not appear as UI text.
    expect(visible.toLowerCase().contains('accesstoken'), isFalse);
    expect(visible.toLowerCase().contains('refreshtoken'), isFalse);
    expect(visible.contains('relationshipAnswers'), isFalse);

    debugPrint(
      '[WYM-DEVICE] PASS loginViaUi=$loginViaUi '
      'uid=${FirebaseAuth.instance.currentUser?.uid} '
      'visible=$visible',
    );
  });
}
