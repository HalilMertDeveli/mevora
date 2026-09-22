// Two-device ghost-user acceptance — DEVICE B side.
//
// Runs on the peer's real Flutter session while QA User A deletes their account
// from a second device. Prints [QA] STAGE markers the host orchestrator watches:
//
//   DISCOVER_POSITIVE_OK  -> host may now seed the match + messages
//   CHAT_POSITIVE_OK      -> host may now run the deletion test on device A
//   IMMEDIATE_OK          -> post-deletion checks passed without restarting B
//
// The session is never restarted here; that is ghost_user_b_restart_test.dart.

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ghost_user_b', (tester) async {
    if (_emailB.isEmpty || _password.isEmpty) {
      fail('Missing --dart-define QA_B_EMAIL / QA_E2E_PASSWORD');
    }

    await bootstrapForTest(AppEnvironment.development);
    await pumpFor(tester, const Duration(seconds: 3));

    await signIn(tester, email: _emailB, password: _password);
    await waitForShell(tester);
    await dismissBlockers(tester);

    // ---------------------------------------------------------- POSITIVE CONTROL
    // A must be positively visible first; a later absence proves nothing otherwise.
    final discoverHasA = await discoverContains(tester, _nameA);
    expect(discoverHasA, isTrue,
        reason: 'A must be a visible Discover candidate before deletion. '
            'visible=${visibleTexts(tester)}');
    debugPrint('[QA] DISCOVER_POSITIVE_OK');

    // Host seeds the match + messages once it sees the marker above.
    debugPrint('[QA] AWAITING_MATCH');
    final deadline = DateTime.now().add(const Duration(minutes: 8));
    while (DateTime.now().isBefore(deadline)) {
      await openMatches(tester);
      await pumpFor(tester, const Duration(seconds: 5));
      if (anyTextContains(_nameA)) break;
    }
    expect(anyTextContains(_nameA), isTrue,
        reason: 'A must appear in B Matches before deletion. '
            'visible=${visibleTexts(tester)}');
    debugPrint('[QA] MATCH_POSITIVE_OK');

    // Open the shared conversation and prove both sides render.
    final openedChat = await openChatWith(tester, _nameA);
    expect(openedChat, isTrue,
        reason: 'could not open the shared conversation from Matches. '
            'visible=${visibleTexts(tester)}');
    final chatReady = await waitUntil(
      tester,
      () => anyTextContains(_msgB) && anyTextContains(_msgA),
      timeout: const Duration(seconds: 120),
    );
    debugPrint('[QA] CHAT_RENDER msgA=${anyTextContains(_msgA)} '
        'msgB=${anyTextContains(_msgB)} visible=${visibleTexts(tester)}');
    expect(chatReady, isTrue,
        reason: 'shared conversation must render both sides before deletion. '
            'visible=${visibleTexts(tester)}');
    debugPrint('[QA] CHAT_POSITIVE_OK visible=${visibleTexts(tester)}');

    // ------------------------------------------------- DELETION HAPPENS ON DEVICE A
    // B stays on the chat screen with live listeners and warm caches.
    debugPrint('[QA] AWAITING_DELETION');
    final sawDeletion = await waitUntil(
      tester,
      () => anyDeletedLabel() || !anyTextContains(_msgA),
      timeout: const Duration(minutes: 12),
    );
    expect(sawDeletion, isTrue,
        reason: 'B never observed the deletion propagate. '
            'visible=${visibleTexts(tester)}');
    debugPrint('[QA] DELETION_DETECTED visible=${visibleTexts(tester)}');

    // --------------------------------------------- IMMEDIATE CHECKS (NO RESTART)
    // DL-2: B keeps their own history; A's content is gone.
    await pumpFor(tester, const Duration(seconds: 6));
    expect(anyTextContains(_msgB), isTrue,
        reason: "DL-2 violated: B's own message disappeared. visible=${visibleTexts(tester)}");
    expect(anyTextContains(_msgA), isFalse,
        reason: "A's message content still rendered after deletion");
    debugPrint('[QA] CHAT_IMMEDIATE_OK visible=${visibleTexts(tester)}');

    // Tapping the deleted participant must not open an active profile.
    if (await tapTextContaining(tester, _nameA, attempts: 2)) {
      expect(anyTextContains('QA synthetic bio'), isFalse,
          reason: 'deleted profile bio exposed from chat header');
      debugPrint('[QA] PROFILE_TAP_CHECKED visible=${visibleTexts(tester)}');
    } else {
      debugPrint('[QA] PROFILE_TAP_NOT_APPLICABLE (A name no longer rendered)');
    }

    // Matches must not show A as a normal, active account.
    await openMatches(tester);
    await pumpFor(tester, const Duration(seconds: 4));
    await pumpFor(tester, const Duration(seconds: 6));
    final matchesShowsActiveA = anyTextContains(_nameA) && !anyDeletedLabel();
    expect(matchesShowsActiveA, isFalse,
        reason: 'A still listed as an active match. visible=${visibleTexts(tester)}');
    debugPrint('[QA] MATCHES_IMMEDIATE_OK visible=${visibleTexts(tester)}');

    // Discover, same session, no restart. Returning to the tab flips TickerMode,
    // which revalidates the visible stack and evicts the deleted candidate, so
    // A must be gone from the deck fetched before the deletion.
    final discoverStillHasA = await discoverContains(tester, _nameA, maxPasses: 6);
    expect(discoverStillHasA, isFalse,
        reason: 'A survived in the pre-fetched Discover deck after deletion. '
            'visible=${visibleTexts(tester)}');
    expect(anyTextContains('QA synthetic bio'), isFalse,
        reason: 'deleted candidate bio still rendered in Discover');
    debugPrint('[QA] DISCOVER_IMMEDIATE_OK');

    // The feature under test: the retained conversation is still reachable from
    // Matches, as read-only history rather than an active connection.
    await openMatches(tester);
    await pumpFor(tester, const Duration(seconds: 6));
    expect(anyDeletedLabel(), isTrue,
        reason: 'history thread missing from Matches after deletion. '
            'visible=${visibleTexts(tester)}');
    debugPrint('[QA] HISTORY_TILE_OK visible=${visibleTexts(tester)}');

    final historyLabel = deletedLabels.firstWhere(anyTextContains);
    final reopened = await openChatWith(tester, historyLabel);
    expect(reopened, isTrue,
        reason: 'could not reopen the read-only history thread. '
            'visible=${visibleTexts(tester)}');
    await pumpFor(tester, const Duration(seconds: 4));
    expect(anyTextContains(_msgB), isTrue,
        reason: "B's retained history missing after reopening");
    expect(anyTextContains(_msgA), isFalse,
        reason: "A's deleted content resurfaced in the history thread");
    debugPrint('[QA] HISTORY_THREAD_OK visible=${visibleTexts(tester)}');

    debugPrint('[QA] IMMEDIATE_OK');
  }, timeout: const Timeout(Duration(minutes: 30)));
}
