// Shared helpers for the two-device ghost-user acceptance.
// Patterned on integration_test/matching/discover_match_chat_runtime_test.dart.
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/bootstrap.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/features/matching/presentation/widgets/match_connection_tile.dart';

/// Boots the real app inside the test binding.
///
/// bootstrap() installs production error handling; the integration_test binding
/// asserts at teardown that the test left FlutterError.onError and
/// ErrorWidget.builder untouched, so all three are captured and restored.
Future<void> bootstrapForTest(AppEnvironment env) async {
  final prevFlutterOnError = FlutterError.onError;
  final prevPlatformOnError = PlatformDispatcher.instance.onError;
  final prevErrorWidgetBuilder = ErrorWidget.builder;
  await bootstrap(env);
  FlutterError.onError = prevFlutterOnError;
  PlatformDispatcher.instance.onError = prevPlatformOnError;
  ErrorWidget.builder = prevErrorWidgetBuilder;
}

/// Labels the deleted participant can legitimately render as.
const deletedLabels = <String>['Deleted account', 'Silinmiş hesap', 'Silinmiş Kullanıcı'];

Future<void> pumpFor(
  WidgetTester tester,
  Duration total, {
  Duration step = const Duration(milliseconds: 200),
}) async {
  final end = DateTime.now().add(total);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
  }
}

String visibleTexts(WidgetTester tester) {
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

/// True when [finder] appears before [timeout]; never fails the test itself.
Future<bool> waitUntil(
  WidgetTester tester,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (predicate()) return true;
  }
  return false;
}

/// Onstage only. The app shell keeps every tab alive in an IndexedStack, so
/// `skipOffstage: false` would match the Discover card while Matches is showing
/// and report text the user cannot actually see.
bool anyTextContains(String needle) =>
    find.textContaining(needle).evaluate().isNotEmpty;

bool anyDeletedLabel() => deletedLabels.any(anyTextContains);

/// Taps the first widget whose text contains [needle], re-resolving the finder
/// on each attempt. Live Firestore listeners rebuild these lists constantly, so
/// a finder captured a frame earlier can be stale by the time the tap lands.
Future<bool> tapTextContaining(
  WidgetTester tester,
  String needle, {
  int attempts = 6,
  Duration settle = const Duration(seconds: 5),
}) async {
  for (var i = 0; i < attempts; i++) {
    final finder = find.textContaining(needle, skipOffstage: false);
    if (finder.evaluate().isNotEmpty) {
      try {
        await tester.tap(finder.first, warnIfMissed: false);
        await pumpFor(tester, settle);
        return true;
      } catch (error) {
        debugPrint('[QA] tap retry $i for "$needle": $error');
      }
    }
    await pumpFor(tester, const Duration(seconds: 2));
  }
  return false;
}

Future<void> signIn(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  Object? error;
  await tester.runAsync(() async {
    try {
      await FirebaseAuth.instance.signOut();
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      error = e;
    }
  });
  await pumpFor(tester, const Duration(seconds: 10));
  if (error != null) fail('sign-in failed for $email: $error');
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || uid.isEmpty) fail('sign-in left currentUser null for $email');
  debugPrint('[QA] signed in uid=$uid');
}

const _skipLabels = [
  'Skip for now', 'Şimdilik atla', 'Not now', 'Daha Sonra',
  'Continue without location', 'Konumsuz devam et', 'Later', 'Sonra',
];

Future<void> dismissBlockers(WidgetTester tester) async {
  const labels = _skipLabels;
  for (var i = 0; i < 6; i++) {
    await pumpFor(tester, const Duration(seconds: 1));
    for (final label in labels) {
      final f = find.text(label);
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first, warnIfMissed: false);
        await pumpFor(tester, const Duration(seconds: 2));
      }
    }
  }
}

/// Onboarding gates (location permission, etc.) stand between sign-in and the
/// shell, so they have to be cleared while waiting rather than afterwards.
Future<void> waitForShell(WidgetTester tester) async {
  final end = DateTime.now().add(const Duration(minutes: 3));
  while (DateTime.now().isBefore(end)) {
    await pumpFor(tester, const Duration(seconds: 2));
    if (find.text('Keşfet').evaluate().isNotEmpty ||
        find.text('Discover').evaluate().isNotEmpty) {
      debugPrint('[QA] shell visible');
      return;
    }
    for (final label in _skipLabels) {
      final f = find.text(label);
      if (f.evaluate().isNotEmpty) {
        debugPrint('[QA] gate "$label"');
        await tester.tap(f.first, warnIfMissed: false);
        await pumpFor(tester, const Duration(seconds: 3));
        break;
      }
    }
  }
  fail('app shell never appeared visible=${visibleTexts(tester)}');
}

/// Chat is a pushed route, so the tab bar is gone while it is open. Without
/// this, a later openTab silently no-ops and its assertions pass vacuously.
Future<void> popToShell(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    if (find.text('Matches').evaluate().isNotEmpty ||
        find.text('Eşleşmeler').evaluate().isNotEmpty) {
      return;
    }
    final back = find.byTooltip('Back');
    if (back.evaluate().isNotEmpty) {
      await tester.tap(back.first, warnIfMissed: false);
    } else {
      await tester.binding.handlePopRoute();
    }
    await pumpFor(tester, const Duration(seconds: 3));
  }
}

Future<bool> openTab(WidgetTester tester, List<String> labels) async {
  await popToShell(tester);
  for (final label in labels) {
    final tab = find.text(label);
    if (tab.evaluate().isNotEmpty) {
      await tester.tap(tab.first, warnIfMissed: false);
      await pumpFor(tester, const Duration(seconds: 4));
      return true;
    }
  }
  return false;
}

Future<bool> openDiscover(WidgetTester tester) =>
    openTab(tester, ['Discover', 'Keşfet']);

Future<bool> openMatches(WidgetTester tester) =>
    openTab(tester, ['Matches', 'Eşleşmeler']);

/// Opens the conversation with [partner] from Matches.
///
/// Tapping the tile's name Text is not always the hit target, and the tile also
/// renders the last-message preview — so presence of the message text alone does
/// not mean the chat opened. The composer TextField is the reliable signal.
Future<bool> openChatWith(WidgetTester tester, String partner) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    await openMatches(tester);
    await pumpFor(tester, const Duration(seconds: 3));

    // Target the tile itself rather than any text: the same name also renders on
    // the offstage Discover card, and the tile shows the last-message preview,
    // so text alone identifies neither the row nor a successful navigation.
    final tiles = find.byType(MatchConnectionTile);
    Finder? target;
    for (var i = 0; i < tiles.evaluate().length; i++) {
      final tile = tiles.at(i);
      if (find.descendant(of: tile, matching: find.textContaining(partner))
          .evaluate()
          .isNotEmpty) {
        target = tile;
        break;
      }
    }
    if (target == null) {
      debugPrint('[QA] no match tile for "$partner" yet');
      await pumpFor(tester, const Duration(seconds: 3));
      continue;
    }

    try {
      await tester.tap(target, warnIfMissed: false);
    } catch (error) {
      debugPrint('[QA] chat tap attempt failed: $error');
      await pumpFor(tester, const Duration(seconds: 2));
      continue;
    }
    await pumpFor(tester, const Duration(seconds: 4));
    // The composer is the reliable signal that the chat route actually opened.
    final opened = await waitUntil(
      tester,
      () => find.byType(TextField).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 25),
    );
    if (opened) {
      debugPrint('[QA] chat opened with $partner');
      return true;
    }
  }
  return false;
}

/// Pages the Discover deck looking for [name], passing cards it does not match.
/// Returns true as soon as the name is on screen.
Future<bool> discoverContains(
  WidgetTester tester,
  String name, {
  int maxPasses = 8,
}) async {
  await openDiscover(tester);
  await pumpFor(tester, const Duration(seconds: 6));
  for (var i = 0; i <= maxPasses; i++) {
    await dismissBlockers(tester);
    if (anyTextContains(name)) return true;
    final pass = find.byIcon(Icons.close_rounded);
    if (pass.evaluate().isEmpty) break;
    await tester.tap(pass.first, warnIfMissed: false);
    await pumpFor(tester, const Duration(seconds: 3));
  }
  return anyTextContains(name);
}
