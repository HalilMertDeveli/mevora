// Phase 12 — Physical-device WYM edge closure (REAL Firebase development = mevora-d6ed0).
// Modes via dart-define WYM_DEVICE_MODE:
//   success (default) — reason cards + second open + security
//   empty — open WYM_EMPTY_B match expect empty UI
//   offline — expect error UI (host must disable network before open)
//
// Prereq:
//   node functions/scripts/whyYouMatchedPhase11DeviceFixture.cjs
//   node functions/scripts/whyYouMatchedPhase12EmptyFixture.cjs  (for empty mode)
// Run with flutter drive (see tool/phase12_device_drive.ps1).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mevora/bootstrap.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/features/compatibility/presentation/why_you_matched/match_why_you_matched_entry.dart';
import 'package:mevora/features/matching/presentation/pages/matches_page.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';

Future<void> _waitCallableReady() async {
  // Allow App Check debug token + Auth ID token to settle before callables.
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
  return texts.take(80).join(' | ');
}

List<String> _visibleTextList(WidgetTester tester) {
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
  return texts;
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
      debugPrint('[WYM-P12] shell visible');
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
    'Remind me later',
    'Sonra hatırlat',
    'No thanks',
    'Hayır, teşekkürler',
  ];
  for (var i = 0; i < 8; i++) {
    await _pumpFor(tester, const Duration(seconds: 1));
    for (final label in dismissLabels) {
      final finder = find.text(label);
      if (finder.evaluate().isNotEmpty) {
        debugPrint('[WYM-P12] dismiss $label');
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
const _nameEmpty = String.fromEnvironment(
  'WYM_DEVICE_NAME_EMPTY',
  defaultValue: 'WYM_EMPTY_B',
);
const _projectId = String.fromEnvironment(
  'WYM_DEVICE_PROJECT',
  defaultValue: 'mevora-d6ed0',
);
const _mode = String.fromEnvironment(
  'WYM_DEVICE_MODE',
  defaultValue: 'success',
);

Map<String, String> _loadCredentials() {
  if (_emailA.isEmpty || _password.isEmpty) {
    fail(
      'Missing dart-defines WYM_DEVICE_EMAIL_A / WYM_DEVICE_PASSWORD.',
    );
  }
  if (_projectId != 'mevora-d6ed0') {
    fail('Refusing non-development projectId=$_projectId');
  }
  return {
    'emailA': _emailA,
    'password': _password,
    'nameB': _nameB,
    'nameEmpty': _nameEmpty,
    'projectId': _projectId,
    'mode': _mode,
  };
}

Future<void> _signInRealAuth(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  debugPrint('[WYM-P12] real Firebase Auth signIn $email');
  await tester.runAsync(() async {
    await FirebaseAuth.instance.signOut();
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _waitCallableReady();
  });
  await _pumpFor(tester, const Duration(seconds: 4));
  expect(FirebaseAuth.instance.currentUser?.uid, isNotNull);
}

Future<bool> _tryLoginUi(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  for (final label in ['Continue with email', 'E-posta ile devam et']) {
    final btn = find.text(label);
    if (btn.evaluate().isNotEmpty) {
      debugPrint('[WYM-P12] Login UI: tap $label');
      await tester.tap(btn.first);
      await _pumpFor(tester, const Duration(seconds: 2));
      break;
    }
  }
  final fields = find.byType(TextField);
  if (fields.evaluate().length < 2) {
    debugPrint('[WYM-P12] Login UI fields not ready — Auth SDK fallback');
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

  Finder partner = find.textContaining(partnerLabel);
  if (partner.evaluate().isEmpty) {
    // Scroll match list for the partner.
    for (var i = 0; i < 8; i++) {
      if (find.textContaining(partnerLabel).evaluate().isNotEmpty) break;
      final scrollables = find.byType(Scrollable);
      if (scrollables.evaluate().isNotEmpty) {
        await tester.drag(scrollables.first, const Offset(0, -250));
        await _pumpFor(tester, const Duration(milliseconds: 400));
      }
    }
    partner = find.textContaining(partnerLabel);
  }
  if (partner.evaluate().isEmpty) {
    partner = find.byType(MatchListTile);
  }
  await _waitFor(tester, partner, label: 'match list item $partnerLabel');
  await tester.tap(partner.first);
  await _pumpFor(tester, const Duration(seconds: 5));
  await _waitFor(tester, find.byType(TextField), label: 'Chat composer');
  debugPrint('[WYM-P12] Chat opened for $partnerLabel');
}

Future<void> _tapWymEntry(WidgetTester tester) async {
  await _dismissBlockers(tester);
  for (var i = 0; i < 6; i++) {
    if (find.byType(MatchWhyYouMatchedEntry).evaluate().isNotEmpty ||
        find.text('Neden Eşleştiniz?').evaluate().isNotEmpty ||
        find.text('Why You Matched').evaluate().isNotEmpty) {
      break;
    }
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isNotEmpty) {
      await tester.drag(scrollables.first, const Offset(0, -200));
      await _pumpFor(tester, const Duration(milliseconds: 400));
    }
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
  debugPrint('[WYM-P12] WYM entry tapped');
  await _pumpFor(tester, const Duration(seconds: 1));
}

Future<bool> _sawLoading(WidgetTester tester) async {
  final end = DateTime.now().add(const Duration(seconds: 8));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
      debugPrint('[WYM-P12] loading visible');
      return true;
    }
    // Already resolved?
    final texts = _visibleTextList(tester);
    if (texts.any((t) =>
        t.contains('Your sense of humor') ||
        t.contains('Mizah anlayışınız') ||
        t.contains('Not enough in common') ||
        t.contains('Henüz yeterli') ||
        t.contains('could not load') ||
        t.contains('yüklenemedi') ||
        t == 'Retry' ||
        t == 'Yeniden dene')) {
      return false;
    }
  }
  return false;
}

Future<String> _waitForWymOutcome(WidgetTester tester) async {
  final end = DateTime.now().add(const Duration(seconds: 75));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    final texts = _visibleTextList(tester);
    final joined = texts.join(' | ');
    final hasHumorEn = texts.any((t) => t.contains('Your sense of humor'));
    final hasHumorTr = texts.any((t) => t.contains('Mizah anlayışınız'));
    final hasEmpty = texts.any(
      (t) =>
          t.contains('Not enough in common') ||
          t.contains('Henüz yeterli ortak'),
    );
    final hasError = texts.any(
      (t) =>
          t.contains('could not load') ||
          t.contains('yüklenemedi') ||
          t.contains('Bağlantını kontrol') ||
          t.contains('check your connection') ||
          t.contains('Something went wrong') ||
          t.contains('Bir şeyler ters'),
    );
    final hasRetry =
        texts.contains('Retry') || texts.contains('Yeniden dene');
    final hasTitle = texts.contains('Why You Matched') ||
        texts.contains('Neden Eşleştiniz?');

    if (hasHumorEn || hasHumorTr) {
      debugPrint('[WYM-P12] SUCCESS reasons visible=$joined');
      return 'success';
    }
    if (hasEmpty) {
      debugPrint('[WYM-P12] EMPTY visible=$joined');
      return 'empty';
    }
    if (hasError || (hasRetry && find.byType(MevoraEmptyState).evaluate().isNotEmpty)) {
      debugPrint('[WYM-P12] ERROR visible=$joined');
      return 'error';
    }
    if (hasTitle && find.byType(MevoraEmptyState).evaluate().isNotEmpty) {
      debugPrint('[WYM-P12] EMPTY/ERROR sheet visible=$joined');
      return hasRetry ? 'error' : 'empty';
    }
  }
  fail('WYM outcome timeout visible=${_visibleTexts(tester)}');
}

Future<void> _dismissSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(20, 40));
  await _pumpFor(tester, const Duration(seconds: 2));
  // Fallback: system back if still open.
  if (find.text('Your sense of humor is similar.').evaluate().isNotEmpty ||
      find.textContaining('Mizah anlayışınız').evaluate().isNotEmpty ||
      find.byType(MevoraEmptyState).evaluate().isNotEmpty) {
    await tester.pageBack();
    await _pumpFor(tester, const Duration(seconds: 2));
  }
}

void _assertNoSensitive(String visible) {
  final lower = visible.toLowerCase();
  expect(lower.contains('accesstoken'), isFalse);
  expect(lower.contains('refreshtoken'), isFalse);
  expect(visible.contains('relationshipAnswers'), isFalse);
  expect(RegExp(r'\blat\b', caseSensitive: false).hasMatch(visible) &&
          RegExp(r'\blng\b', caseSensitive: false).hasMatch(visible),
      isFalse);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    if (message.contains('HTTP request failed') ||
        message.contains('NetworkImageLoadException')) {
      debugPrint('[WYM-P12] ignored image error: $message');
      return;
    }
    defaultOnError?.call(details);
  };

  testWidgets('why_you_matched_phase12_device_e2e', (tester) async {
    final qa = _loadCredentials();
    final mode = qa['mode']!;
    debugPrint('[WYM-P12] mode=$mode');

    await bootstrap(AppEnvironment.development);
    await _pumpFor(tester, const Duration(seconds: 3));

    await tester.runAsync(() async {
      await FirebaseAuth.instance.signOut();
    });
    await _pumpFor(tester, const Duration(seconds: 2));

    final loginViaUi = await _tryLoginUi(
      tester,
      email: qa['emailA']!,
      password: qa['password']!,
    );
    if (!loginViaUi) {
      await _signInRealAuth(
        tester,
        email: qa['emailA']!,
        password: qa['password']!,
      );
    }
    await tester.runAsync(() async {
      await _waitCallableReady();
    });

    await _waitForShell(tester);
    await _dismissBlockers(tester);

    final partner = mode == 'empty' ? qa['nameEmpty']! : qa['nameB']!;
    await _openMatchChat(tester, partner);
    expect(find.byType(TextField), findsWidgets);

    await _tapWymEntry(tester);
    final sawLoading = await _sawLoading(tester);
    final outcome = await _waitForWymOutcome(tester);
    final visible = _visibleTexts(tester);
    _assertNoSensitive(visible);

    if (mode == 'success') {
      expect(outcome, 'success');
      final texts = _visibleTextList(tester);
      final hasHumorTitle = texts.any(
        (t) =>
            t.contains('Your sense of humor is similar.') ||
            t.contains('Mizah anlayışınız benziyor.'),
      );
      expect(hasHumorTitle, isTrue, reason: 'individual reason card title missing: $visible');
      final hasEvidence = texts.any(
        (t) =>
            t.contains('similar choices') ||
            t.contains('sorunun') ||
            t.contains('humor style') ||
            t.contains('mizah stili') ||
            t.contains('humor profiles') ||
            t.contains('Mizah profilleriniz'),
      );
      expect(hasEvidence, isTrue, reason: 'reason description/evidence missing: $visible');
      debugPrint('[WYM-P12] reasonCards PASS loadingSeen=$sawLoading');

      // Second open — close sheet and reopen (cache may warm).
      await _dismissSheet(tester);
      await _tapWymEntry(tester);
      final second = await _waitForWymOutcome(tester);
      expect(second, 'success');
      debugPrint(
        '[WYM-P12] secondOpen PASS cacheHit=NOT_OBSERVABLE_ON_DEVICE '
        '(UI success consistent)',
      );
    } else if (mode == 'empty') {
      expect(outcome, 'empty');
      debugPrint('[WYM-P12] empty PASS');
    } else if (mode == 'offline') {
      expect(outcome, 'error');
      final hasRetry = find.text('Retry').evaluate().isNotEmpty ||
          find.text('Yeniden dene').evaluate().isNotEmpty;
      expect(hasRetry, isTrue, reason: 'retry action missing on error: $visible');
      debugPrint('[WYM-P12] offline/error PASS — host should restore network then retry');

      // Host restores network; wait then tap Retry.
      final retryEnd = DateTime.now().add(const Duration(seconds: 90));
      var recovered = false;
      while (DateTime.now().isBefore(retryEnd)) {
        await tester.pump(const Duration(milliseconds: 500));
        final retry = find.text('Retry').evaluate().isNotEmpty
            ? find.text('Retry')
            : find.text('Yeniden dene');
        if (retry.evaluate().isNotEmpty) {
          await tester.tap(retry.first, warnIfMissed: false);
          debugPrint('[WYM-P12] Retry tapped');
          await _pumpFor(tester, const Duration(seconds: 2));
          final after = await _waitForWymOutcome(tester);
          if (after == 'success' || after == 'empty') {
            recovered = true;
            debugPrint('[WYM-P12] retry recovery PASS outcome=$after');
            break;
          }
        }
      }
      expect(recovered, isTrue, reason: 'retry did not recover after network restore');
    } else {
      fail('Unknown WYM_DEVICE_MODE=$mode');
    }

    debugPrint(
      '[WYM-P12] PASS mode=$mode loginViaUi=$loginViaUi '
      'uid=${FirebaseAuth.instance.currentUser?.uid} '
      'loadingSeen=$sawLoading visible=$visible',
    );
  });
}
