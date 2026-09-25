// Live QA: Discover → Like → Mutual Match → Chat → A↔B messages.
// Prereq: node tool/seedMatchingRuntimeQa.cjs
// Run (PowerShell):
//   $token = (Get-Content tool/app_check_debug_token.local -Raw).Trim()
//   flutter test integration_test/matching/discover_match_chat_runtime_test.dart -d emulator-5556 `
//     --dart-define=FIREBASE_APP_CHECK_DEBUG_TOKEN=$token `
//     --dart-define=QA_A_EMAIL=sen@gmail.com `
//     --dart-define=QA_B_EMAIL=hilaltokusledajans@gmail.com `
//     --dart-define=QA_E2E_PASSWORD=<from seed env>

import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mevora/bootstrap.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/shared/animations/mevora_match_celebration.dart';

const _emailA = String.fromEnvironment('QA_A_EMAIL');
const _emailB = String.fromEnvironment('QA_B_EMAIL');
const _password = String.fromEnvironment('QA_E2E_PASSWORD');
const _nameA = String.fromEnvironment('QA_A_NAME', defaultValue: 'QA_A');
const _nameB = String.fromEnvironment('QA_B_NAME', defaultValue: 'QA_B');
const _messageA = 'QA test message A';
const _messageB = 'QA test message B';

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
  return texts.take(40).join(' | ');
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
        find.text('Discover').evaluate().isNotEmpty) {
      debugPrint('[QA] shell visible');
      return;
    }
  }
  fail('Timeout waiting for App shell Discover tab visible=${_visibleTexts(tester)}');
}

Future<Map<String, String>> _qaCredentials() async {
  if (_emailA.isEmpty || _emailB.isEmpty || _password.isEmpty) {
    fail(
      'Missing QA dart-defines (QA_A_EMAIL, QA_B_EMAIL, QA_E2E_PASSWORD). '
      'Run seed then pass --dart-define values.',
    );
  }
  return {
    'emailA': _emailA,
    'emailB': _emailB,
    'password': _password,
    'nameA': _nameA,
    'nameB': _nameB,
  };
}

Future<void> _signIn(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  debugPrint('[QA] signIn $email');
  Object? signInError;
  await tester.runAsync(() async {
    try {
      await FirebaseAuth.instance.signOut();
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      debugPrint('[QA] credential uid=${cred.user?.uid}');
    } catch (error) {
      signInError = error;
      debugPrint('[QA] signIn error=$error');
    }
  });
  await _pumpFor(tester, const Duration(seconds: 10));
  final uid = FirebaseAuth.instance.currentUser?.uid;
  debugPrint('[QA] signed in uid=$uid');
  if (signInError != null) {
    fail('Firebase sign-in failed for $email: $signInError');
  }
  if (uid == null || uid.isEmpty) {
    fail('Firebase sign-in left currentUser null for $email');
  }
}

Future<void> _dismissBlockers(WidgetTester tester) async {
  final dismissLabels = [
    'Not now',
    'Daha Sonra',
    'Şimdilik atla',
    'Continue without location',
    'Konumsuz devam et',
    'Skip for now',
  ];
  for (var i = 0; i < 8; i++) {
    await _pumpFor(tester, const Duration(seconds: 1));
    for (final label in dismissLabels) {
      final finder = find.text(label);
      if (finder.evaluate().isNotEmpty) {
        debugPrint('[QA] dismiss $label');
        await tester.tap(finder.first);
        await _pumpFor(tester, const Duration(seconds: 2));
      }
    }
  }
}

Future<void> _openDiscoverTab(WidgetTester tester) async {
  for (final label in ['Discover', 'Keşfet']) {
    final tab = find.text(label);
    if (tab.evaluate().isNotEmpty) {
      debugPrint('[QA] open tab $label');
      await tester.tap(tab.first);
      await _pumpFor(tester, const Duration(seconds: 3));
      return;
    }
  }
}

Future<void> _waitForDiscoverDeck(WidgetTester tester) async {
  await _openDiscoverTab(tester);
  await _waitFor(
    tester,
    find.byIcon(Icons.favorite_rounded),
    timeout: const Duration(seconds: 180),
    label: 'Discover like button',
  );
}

Future<void> _tapLike(WidgetTester tester) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    await _dismissBlockers(tester);
    final likeButtons = find.byIcon(Icons.favorite_rounded);
    if (likeButtons.evaluate().isEmpty) {
      await _pumpFor(tester, const Duration(seconds: 2));
      continue;
    }
    final like = likeButtons.last;
    await tester.ensureVisible(like);
    await _pumpFor(tester, const Duration(milliseconds: 500));
    await _dismissBlockers(tester);
    await tester.tap(like, warnIfMissed: false);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 6));
    });
    await _pumpFor(tester, const Duration(seconds: 4));
    return;
  }
  fail('Could not tap Discover like button visible=${_visibleTexts(tester)}');
}

Future<void> _likePartner(
  WidgetTester tester, {
  required String partnerLabel,
}) async {
  var attempts = 0;
  while (attempts < 15) {
    await _dismissBlockers(tester);
    final partner = find.textContaining(partnerLabel);
    if (partner.evaluate().isNotEmpty) {
      debugPrint('[QA] found partner $partnerLabel');
      await _tapLike(tester);
      return;
    }
    final passButton = find.byIcon(Icons.close_rounded);
    if (passButton.evaluate().isEmpty) {
      break;
    }
    debugPrint('[QA] pass card attempt=$attempts');
    await tester.tap(passButton.first, warnIfMissed: false);
    await _pumpFor(tester, const Duration(seconds: 3));
    attempts += 1;
  }
  fail('Partner $partnerLabel not found in Discover deck after $attempts passes');
}

Future<void> _waitForMatchCelebration(WidgetTester tester) async {
  final end = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(end)) {
    await _dismissBlockers(tester);
    await tester.pump(const Duration(milliseconds: 200));
    if (find.byType(MevoraMatchCelebration).evaluate().isNotEmpty ||
        find.text('Send message').evaluate().isNotEmpty ||
        find.text('Mesaj gönder').evaluate().isNotEmpty ||
        find.textContaining('IT\'S A MATCH').evaluate().isNotEmpty ||
        find.textContaining('BİR EŞLEŞMENİZ VAR').evaluate().isNotEmpty) {
      debugPrint('[QA] match UI visible=${_visibleTexts(tester)}');
      return;
    }
  }
  fail('Timeout waiting for Match celebration visible=${_visibleTexts(tester)}');
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
  fail('Matches tab not found');
}

Future<void> _openChatWithPartner(WidgetTester tester, String partnerLabel) async {
  await _openMatchesTab(tester);
  await _waitFor(
    tester,
    find.textContaining(partnerLabel),
    label: 'Match list tile $partnerLabel',
  );
  await tester.tap(find.textContaining(partnerLabel).first);
  await _pumpFor(tester, const Duration(seconds: 5));
  await _waitFor(
    tester,
    find.byType(TextField),
    label: 'Chat composer',
  );
}

Future<void> _sendChatMessage(WidgetTester tester, String text) async {
  final composer = find.byType(TextField);
  expect(composer, findsOneWidget);
  await tester.enterText(composer, text);
  await tester.pump();
  final send = find.byIcon(Icons.send_rounded);
  expect(send, findsOneWidget);
  await tester.tap(send);
  await _pumpFor(tester, const Duration(seconds: 8));
  await _waitFor(
    tester,
    find.text(text),
    label: 'Sent message $text',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'discover_match_chat_runtime_test',
    (tester) async {
    final qa = await _qaCredentials();
    final emailA = qa['emailA']!;
    final emailB = qa['emailB']!;
    final password = qa['password']!;
    final nameA = qa['nameA']!;
    final nameB = qa['nameB']!;

    // Development activates App Check debug provider (required on emulator).
    // Project remains mevora-d6ed0 (live QA backend).
    // Preserve test binding error handlers — bootstrap overrides them.
    final previousFlutterOnError = FlutterError.onError;
    final previousPlatformOnError = PlatformDispatcher.instance.onError;
    await bootstrap(AppEnvironment.development);
    FlutterError.onError = previousFlutterOnError;
    PlatformDispatcher.instance.onError = previousPlatformOnError;
    await _pumpFor(tester, const Duration(seconds: 3));

    // A → like B (one-way)
    await _signIn(tester, email: emailA, password: password);
    await _waitForShell(tester);
    await _dismissBlockers(tester);
    await _waitForDiscoverDeck(tester);
    await _likePartner(tester, partnerLabel: nameB);
    expect(find.byType(MevoraMatchCelebration), findsNothing);

    // B → like A → mutual match UI
    await _signIn(tester, email: emailB, password: password);
    await _waitForShell(tester);
    await _dismissBlockers(tester);
    await _waitForDiscoverDeck(tester);
    await _likePartner(tester, partnerLabel: nameA);
    await _waitForMatchCelebration(tester);

    // Match → Chat via Send message
    final sendEn = find.text('Send message');
    final sendTr = find.text('Mesaj gönder');
    if (sendEn.evaluate().isNotEmpty) {
      await tester.tap(sendEn.first);
    } else if (sendTr.evaluate().isNotEmpty) {
      await tester.tap(sendTr.first);
    } else {
      fail('Send message button missing');
    }
    await _pumpFor(tester, const Duration(seconds: 5));
    await _waitFor(
      tester,
      find.byType(TextField),
      label: 'Chat after match',
    );

    // B → A message
    await _sendChatMessage(tester, _messageB);

    // A reads B message
    await _signIn(tester, email: emailA, password: password);
    await _openChatWithPartner(tester, nameB);
    expect(find.text(_messageB), findsOneWidget);

    // A → B message + keyboard exercise
    final composer = find.byType(TextField);
    await tester.tap(composer);
    await tester.pump();
    await _sendChatMessage(tester, _messageA);

    // B reads A message
    await _signIn(tester, email: emailB, password: password);
    await _openChatWithPartner(tester, nameA);
    expect(find.text(_messageA), findsOneWidget);
    expect(find.text(_messageB), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 15)));
}
