# MEVORA — MATCHING QA PHASE 2 FINAL

**Date:** 2026-08-28  
**Branch:** `feature/spotify-music-compatibility`  
**Worktree:** `D:\Mevora`  
**Firebase project:** `mevora-d6ed0`  
**Previous phase:** Matching QA FAZ 1 — Runtime Verification (`MATCHING_RUNTIME_QA_PHASE_1.md`)  
**Previous decision:** NOT PRODUCTION READY  
**Git actions this phase:** none (no commit / merge / push / branch switch)

---

## 1. Executive Summary

FAZ 2 resolved the **music compatibility compile blocker** and fixed the **app_launch** assertion bug. Emulator `app_launch_test` now **PASS**es with a real `MaterialApp` bootstrap.

The critical Discover → Like → Mutual Match → Match Screen → Chat → A↔B message chain is still **not PASS on LIVE FLUTTER UI**.

`discover_match_chat_runtime_test` was rebuilt on this branch and run on emulator + physical Android. Emulator run authenticated QA_A successfully, then **timed out waiting for the Discover like button**. Physical runs hung / failed without completing the flow.

Backend matching callables remain deployed. Live callable mutual-match via App Check JWT was **not re-confirmed** in this phase (password/custom-token signer limitations on ADC); Admin-SDK schema probe reported overall PASS with admin fallback — that is **not** a Flutter UI PASS.

**Final decision: NOT PRODUCTION READY**

---

## 2. Previous Blockers

| # | FAZ 1 blocker | FAZ 2 status |
|---|---------------|--------------|
| 1 | Discover → Like → Mutual Match → Match → Chat not PASS on Flutter UI | **OPEN** — FAIL |
| 2 | Message A→B not verified on Flutter UI | **OPEN** — NOT TESTED |
| 3 | Message B→A not verified on Flutter UI | **OPEN** — NOT TESTED |
| 4 | Chat keyboard/scroll not verified | **OPEN** — NOT TESTED |
| 5 | `discover_match_chat_runtime_test` FAIL/TIMEOUT | **OPEN** — FAIL (timeout on Discover deck) |
| 6 | `app_launch_test` retest compile/bootstrap | **RESOLVED** on emulator (MaterialApp fix) |
| 7 | Physical Android QA | **OPEN** — NOT TESTED / incomplete |
| 8 | iOS QA | **OPEN** — NOT TESTED (Windows host) |
| 9 | MATCHING_STREAK | **OPEN** — deployed functions ACTIVE; client source absent on this branch; NOT TESTED |
| 10 | Music compatibility compile errors | **RESOLVED** (UTF-16 corruption restored; analyze 0 errors) |

---

## 3. Root Causes

### 3.1 Music compile / integration rebuild

- Working copies of `match_music_compatibility_banner.dart` and `music_compatibility_sheet.dart` were **UTF-16 corrupted**.
- HEAD on this branch already contains valid UTF-8 music compatibility API (`overallCompatibilityScore`, recent artists, etc.).
- FAZ 1 compile errors were from corrupted/stale files, not missing entity fields on this branch.

### 3.2 `app_launch_test`

- Assertion used `find.byType(Object)` (always true / meaningless).
- Retest failures were compounded by the music UTF-16 compile blocker.

### 3.3 `discover_match_chat_runtime_test` (this branch)

- Test file was **missing** on `feature/spotify-music-compatibility` (created during FAZ 1 on another branch).
- Recreated with email/password QA sign-in (custom tokens require service-account `signBlob`, unavailable via firebase-tools ADC).
- After successful `signIn` (uid `F7CYZWNik3RGv3xQTZRLKWsMnTd2`), UI never showed Discover like (`Icons.favorite_rounded`) within 180s.
- Likely causes (not fully isolated):
  - Location / relationship / empty-deck / loading / locale UI gate still blocking Discover actions
  - AuthController stream may take longer than pumps to reach shell Discover
  - QA feed may not present partner card quickly enough for the automation path

### 3.4 Live callable E2E

- `firebase-admin` custom tokens fail without SA signer (`signBlob` / metadata).
- Password path sometimes returned `INVALID_LOGIN_CREDENTIALS` in the probe (ADC can update passwords; Identity Toolkit sign-in still flaky in the same session).
- Probe fell back to Admin-written match documents → **not** live Flutter / not live callable PASS for Discover UI.

---

## 4. Fixes

| Fix | Files | Scope |
|-----|-------|-------|
| Restore corrupted music UI / l10n sources | `git checkout HEAD --` banner, sheet, music l10n JSON | Compile only |
| `app_launch_test` asserts real `MaterialApp` | `integration_test/smoke/app_launch_test.dart` | Bootstrap smoke |
| QA ADC bootstrap | `tool/qaBootstrapAdcFromFirebaseLogin.cjs` | Local Admin SDK |
| QA seed (clear likes/match, pause relationship overlay, set QA password) | `tool/seedMatchingRuntimeQa.cjs` | Test prep |
| Discover like backend probe (restored) | `tool/discoverLikeQaE2e.cjs` | LIVE BACKEND probe |
| Runtime integration test (recreated) | `integration_test/matching/discover_match_chat_runtime_test.dart` | LIVE FLUTTER UI attempt |
| Gitignore local QA fixture | `.gitignore` | Secrets/fixture hygiene |

**Not changed (preserved):** matching math, catalog, `recordDiscoveryDecision` / `recordSwipe` transaction logic, App Check enforcement, Firestore auth model, E2EE, compatibility engine.

---

## 5. Discover UI

| Result | **FAIL / NOT TESTED as PASS** |
| Test type | INTEGRATION TEST (emulator) attempted LIVE FLUTTER UI |
| Device | `emulator-5556` |
| Evidence | Auth PASS (`uid=F7CYZWNik3RGv3xQTZRLKWsMnTd2`); timeout waiting for Discover like button |
| QA users | QA_A / QA_B |

---

## 6. Like UI

| Result | **NOT TESTED** (blocked by Discover deck timeout) |
| Test type | INTEGRATION TEST |
| Device | emulator-5556 / SM M225FV attempted |

---

## 7. Mutual Match UI

| Result | **NOT TESTED** on LIVE FLUTTER UI |
| Backend note | Admin fallback match schema probe only — **not** UI PASS |

---

## 8. Match Screen

| Result | **NOT TESTED** |

---

## 9. Chat UI

| Result | **NOT TESTED** on LIVE FLUTTER UI |
| Unit/widget | chat suite had **1 FAIL** (`chat_voice_rules_test.dart`) unrelated to matching flow |

---

## 10. Message A→B

| Result | **NOT TESTED** (LIVE FLUTTER UI) |

---

## 11. Message B→A

| Result | **NOT TESTED** (LIVE FLUTTER UI) |

---

## 12. Keyboard

| Result | **NOT TESTED** |

---

## 13. Scroll

| Result | **NOT TESTED** |

---

## 14. App Launch Integration

| Result | **PASS** (emulator) |
| Test type | INTEGRATION TEST |
| Device | `emulator-5556` (EMULATOR) |
| Evidence | `flutter test integration_test/smoke/app_launch_test.dart -d emulator-5556` → All tests passed |
| Physical | Incomplete / FAIL (process IO cleanup after hang) — **NOT PASS** |

---

## 15. Discover Match Chat Integration

| Result | **FAIL** |
| Test type | INTEGRATION TEST |
| Device | `emulator-5556` |
| Evidence | Timeout waiting for Discover like button after QA_A sign-in |
| Physical (`R68T305S3VM`) | Hung ~7+ minutes without pass/fail assertion result — treated as **FAIL / incomplete** |

---

## 16. MATCHING_STREAK

| Result | **NOT TESTED** |
| Deployed | `getMatchingStreak`, `matchingStreakReminderTick` = **ACTIVE** (europe-west1) |
| This branch source | **No** `matchingStreak` / `getMatchingStreak` references in `lib/` or `functions/src/` |
| Client wiring | **Not verified** on this branch |
| Verdict label | Deployed backend symbols exist; **NOT IMPLEMENTED in this branch source** / **NOT TESTED** end-to-end |

---

## 17. Hourly Matching Regression

| Result | **NOT TESTED** on this branch |
| Deployed | `getMatchingGameRound`, `joinMatchingGameRound`, `submitMatchingGameAnswers`, `runMatchingGameRoundNow`, `getMatchingGameResult`, `matchingGameHourlyTick` = ACTIVE |
| Local scripts | `functions/scripts/` **absent** on this branch |
| App Check | Left **ENFORCED** (not disabled) |

---

## 18. Compatibility Regression

| Result | **NOT REGRESSED in code review** / **NOT LIVE-RETESTED** |
| Notes | No compatibility engine / reveal logic edits this phase. Music UI files restored from HEAD only. |

---

## 19. App Check

| Status | **ENFORCED** |
| Debug token | Used only via `--dart-define=FIREBASE_APP_CHECK_DEBUG_TOKEN` / `tool/app_check_debug_token.local` (gitignored) |
| Token values | **Not logged / not committed / not printed in this report** |

---

## 20. Security

- No App Check disable.
- No Firestore rules / auth model changes.
- No secrets committed.
- Local fixture `matching_runtime_qa.local.json` gitignored.
- QA password reset for automation is local-only via Admin SDK; not written into tracked source.

---

## 21. Emulator QA

| Device | `emulator-5556` (sdk gphone16k x86 64, Android 17) |
| app_launch | **PASS** |
| discover_match_chat_runtime | **FAIL** (Discover like timeout) |
| Overall emulator critical flow | **FAIL** |

Also present: `emulator-5554` (not used for final matrix).

---

## 22. Physical Android QA

| Device | Samsung SM M225FV (`R68T305S3VM`), Android 13 — **PHYSICAL** |
| discover_match_chat_runtime | Incomplete / hung — **NOT PASS** |
| app_launch | Incomplete / failed cleanup — **NOT PASS** |
| Label | **PHYSICAL ANDROID — NOT TESTED** (no successful end-to-end evidence) |

---

## 23. iOS QA

| Result | **iOS — NOT TESTED** |
| Reason | Windows host; no iOS simulator/device |

---

## 24. Unit/Widget Tests

| Suite | Result |
|-------|--------|
| `flutter analyze --no-fatal-infos` | 7 issues, **0 errors** |
| Cloud Functions `npm test` | **88 PASS / 0 FAIL** |
| `test/features/chat` | **36 PASS / 1 FAIL** (`chat_voice_rules_test`) |
| `test/features/discovery` (+ matching subset run) | at least **1 FAIL** in discovery suite during combined run |

Widget PASS ≠ Live Flutter UI PASS.

---

## 25. Integration Tests

| Test | Device | Result |
|------|--------|--------|
| `integration_test/smoke/app_launch_test.dart` | emulator-5556 | **PASS** |
| `integration_test/smoke/app_launch_test.dart` | SM M225FV | incomplete / FAIL |
| `integration_test/matching/discover_match_chat_runtime_test.dart` | emulator-5556 | **FAIL** |
| `integration_test/matching/discover_match_chat_runtime_test.dart` | SM M225FV | incomplete / FAIL |

---

## 26. Live Backend Tests

| Probe | Result | Notes |
|-------|--------|-------|
| `tool/check_match_and_functions.cjs` | Functions inventory OK | Match docs absent before seed (expected) |
| `tool/diagnose_discovery_pair.cjs` | QA_A↔QA_B **INCLUDED** | Photos approved, location present, reciprocal prefs OK |
| `tool/discoverLikeQaE2e.cjs` | overall **PASS** with **admin fallback** | Live callables **SKIPPED** (no SA signer / password path fail) → **not** callable LIVE PASS |
| Hourly Matching E2E | **NOT TESTED** | Scripts missing on branch |

LIVE BACKEND callable Discover Like mutual match: **NOT RECONFIRMED** this phase.

---

## 27. Mock/Fake Tests

- Chat image viewer smoke uses local widget harness (mock media bytes) — not used as critical-flow PASS.
- No mock navigation / fake callable used to claim Discover→Chat PASS.

---

## 28. Remaining Blockers

1. Discover deck / like button not reached in LIVE FLUTTER integration after auth.
2. Mutual Match / Match Screen / Chat not verified on LIVE FLUTTER UI.
3. Message A→B and B→A not verified on LIVE FLUTTER UI.
4. Keyboard / scroll not verified.
5. Physical Android end-to-end not completed.
6. iOS not tested.
7. MATCHING_STREAK not tested; source not on this branch.
8. Hourly Matching live E2E not re-run on this branch.
9. Live callable Discover Like / Mutual Match not reconfirmed (App Check JWT + SA signer gap).
10. Unrelated unit FAIL: `chat_voice_rules_test.dart`.

---

## CRITICAL FLOW TABLE

| Step | Result | Test Type | Device | Evidence |
|---|---|---|---|---|
| Discover | FAIL | INTEGRATION TEST | emulator-5556 | Auth OK; timeout for like button |
| Like | NOT TESTED | — | — | Blocked by Discover |
| Mutual Match | NOT TESTED | — | — | Blocked by Discover |
| Match Screen | NOT TESTED | — | — | Blocked by Discover |
| Chat | NOT TESTED | — | — | Blocked by Discover |
| Message A→B | NOT TESTED | — | — | Blocked by Discover |
| Message B→A | NOT TESTED | — | — | Blocked by Discover |
| Keyboard | NOT TESTED | — | — | Blocked by Discover |

---

## DEVICE MATRIX

| Device | Resolution | Physical/Emulator | Discover | Like | Match | Chat | A→B | B→A | Keyboard | Overall |
|---|---|---|---|---|---|---|---|---|---|---|
| emulator-5556 | n/a | Emulator | FAIL | NT | NT | NT | NT | NT | NT | FAIL |
| SM M225FV | n/a | Physical | NT | NT | NT | NT | NT | NT | NT | NOT TESTED |
| iOS | n/a | — | NT | NT | NT | NT | NT | NT | NT | NOT TESTED |

NT = NOT TESTED

---

## FINAL DECISION

### **NOT PRODUCTION READY**

Required LIVE FLUTTER UI proofs missing:

- Discover → Like
- Mutual Match
- Match Screen
- Chat
- Message A→B
- Message B→A

Also:

- **PHYSICAL DEVICE QA — NOT TESTED**
- **iOS QA — NOT TESTED**
- **MATCHING_STREAK — NOT TESTED**

Music compile blocker: **resolved**.  
App launch (emulator): **PASS**.  
Critical matching UI chain: **still FAIL**.

---

*End of FAZ 2. No commit / merge / push. Do not proceed to FAZ 3 from this report.*
