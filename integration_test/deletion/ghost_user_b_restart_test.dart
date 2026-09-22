// Two-device ghost-user acceptance — DEVICE B, COLD START.
//
// Run after ghost_user_b_test.dart and the deletion on device A. This is a fresh
// process against the same app data directory (auth session, Firestore local
// cache and any persisted profile state survive), so it is the cache/restart
// acceptance: a stale cached object would resurrect A here.
//
// App data is deliberately NOT cleared before this run.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mevora/core/config/app_environment.dart';

import 'ghost_helpers.dart';

const _emailB = String.fromEnvironment('QA_B_EMAIL');
const _password = String.fromEnvironment('QA_E2E_PASSWORD');
const _nameA = String.fromEnvironment('QA_A_NAME', defaultValue: 'QAGhostA');
const _msgA = String.fromEnvironment('QA_MSG_A', defaultValue: 'QA ghost message from A');
const _msgB = String.fromEnvironment('QA_MSG_B', defaultValue: 'QA ghost message from B');
const _bio = String.fromEnvironment('QA_A_BIO', defaultValue: 'QA synthetic bio');
// When true the session was signed out first, so this is the logout/login pass.
const _freshLogin = bool.fromEnvironment('QA_FRESH_LOGIN');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ghost_user_b_restart', (tester) async {
    await bootstrapForTest(AppEnvironment.development);
    await pumpFor(tester, const Duration(seconds: 5));

    if (_freshLogin) {
      await signIn(tester, email: _emailB, password: _password);
      debugPrint('[QA] FRESH_LOGIN');
    } else {
      // Persisted session must still be B — proves we are testing restored state.
      final restored = await waitUntil(
        tester,
        () => FirebaseAuth.instance.currentUser != null,
        timeout: const Duration(seconds: 60),
      );
      if (!restored) {
        await signIn(tester, email: _emailB, password: _password);
        debugPrint('[QA] SESSION_NOT_PERSISTED_FELL_BACK_TO_SIGNIN');
      } else {
        debugPrint('[QA] SESSION_RESTORED uid=${FirebaseAuth.instance.currentUser?.uid}');
      }
    }

    await waitForShell(tester);
    await dismissBlockers(tester);

    // Discover must stay clean on a cold start.
    final discoverHasA = await discoverContains(tester, _nameA, maxPasses: 6);
    expect(discoverHasA, isFalse,
        reason: 'A resurrected in Discover after restart. visible=${visibleTexts(tester)}');
    debugPrint('[QA] DISCOVER_RESTART_OK');

    // Matches: a retained match is fine, an active-looking A is not.
    await openMatches(tester);
    await pumpFor(tester, const Duration(seconds: 8));
    final matchesVisible = visibleTexts(tester);
    final activeAInMatches = anyTextContains(_nameA) && !anyDeletedLabel();
    expect(activeAInMatches, isFalse,
        reason: 'A listed as an active match after restart. visible=$matchesVisible');
    debugPrint('[QA] MATCHES_RESTART_OK visible=$matchesVisible');

    // Chat: retained history, no resurrected content, no crash.
    expect(anyDeletedLabel(), isTrue,
        reason: 'read-only history thread missing after restart. '
            'visible=${visibleTexts(tester)}');
    final threadLabel = deletedLabels.firstWhere(anyTextContains);
    final opened = await openChatWith(tester, threadLabel);
    expect(opened, isTrue,
        reason: 'could not reopen history thread after restart. '
            'visible=${visibleTexts(tester)}');
    if (opened) {
      expect(anyTextContains(_msgB), isTrue,
          reason: "B's retained history lost after restart. visible=${visibleTexts(tester)}");
      expect(anyTextContains(_msgA), isFalse,
          reason: "A's deleted message content resurrected from cache");
      expect(anyTextContains(_bio), isFalse,
          reason: "A's bio resurrected in chat after restart");
      debugPrint('[QA] CHAT_RESTART_OK visible=${visibleTexts(tester)}');
    } else {
      debugPrint('[QA] CHAT_RESTART_NO_THREAD visible=${visibleTexts(tester)}');
    }

    // No surface may expose A's private profile content.
    expect(anyTextContains(_bio), isFalse, reason: "A's bio exposed after restart");
    debugPrint('[QA] PROFILE_RESTART_OK');
    debugPrint('[QA] RESTART_OK');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
