# MEVORA FULL QA REPORT

**Date:** 2026-08-25 (overnight autonomous run)  
**Branch:** `backup/wip-before-device-sync-20260824`  
**Baseline commit:** `dd03fd1` — privacy/security E2EE harden  
**Host:** Windows 11, Flutter 3.41.9  
**Devices:** Emulator `emulator-5554` (API 37) only — **no USB phone**  
**Firebase (dev):** `mevora-d6ed0`  
**iOS:** Not available on this host  

Artifacts: `qa/*.md`, screenshots under `build/qa-parity/`, test logs `qa/*_run.log`.

---

## Overall Status

| Metric | Value |
|--------|-------|
| Feature areas inventoried from code | 28 |
| Flutter automated tests (final) | **654 PASS** |
| Functions tests (final) | **78 PASS** |
| Integration smoke (final) | **PASS** |
| Debug APK | **PASS** |
| Release APK | **PASS** (after registrant fix) |
| Emulator cold start (auth UI) | **PASS** |
| Real-device E2E | **BLOCKED** |
| Dual-user live chat/voice/image | **BLOCKED / NOT TESTABLE** |
| Full signup→delete funnel live | **NOT TESTABLE** |

**Counts (evidence-based):**

- Total Features: 28  
- Total Tests executed (auto): ~733 (654 + 78 + 1 integration)  
- Passed: ~733 after fixes  
- Failed (pre-fix, then fixed): 3 (2 unit + 1 integration + 1 release build)  
- Blocked: Real device, SMS, dual-user, FCM kill, soak, iOS  
- Not Testable: Apple Sign-In on Android, live account delete (intentionally not run on real identity)

---

## Release Status

# 🔴 NOT READY FOR RELEASE

See `RELEASE_READINESS.md`.

---

## Feature inventory (from `lib/` + routes)

Auth (email, Google, Apple, Phone, Spotify) · Onboarding · Location · Discover/swipe/boost · Matches · Likes You (premium) · Chat text/image/voice + E2EE · Calls (LiveKit) · Profile/edit/Q&A · Verification (Sumsub) · Music (Spotify) · Settings (privacy, notifications, blocked, password, export, delete) · Reports/block · Support/legal · Boost IAP · Permissions · FCM  

---

## CRITICAL BUGS

### C1 — Functions missing `incomingLike` FCM types  
Fixed — see `BUGS_FOUND.md` / `FIXES_APPLIED.md`. Regression: functions tests PASS.

### C2 — Release APK broken by `integration_test` in GeneratedPluginRegistrant  
Fixed by regenerating plugins. Release APK builds and boots to auth UI.

---

## HIGH BUGS

H1 Account settings widget test scroll — **Fixed**  
H2 Voice storage rules test drift — **Fixed**  
H3 No physical device — **Open / BLOCKED**  
H4 Rules/functions live deploy not smoked — **Open**  
H5 Integration smoke env mismatch — **Fixed**  
H6 Integration install left package without activities — **Observed / mitigated by reinstall**

---

## MEDIUM / LOW

M1 Debug signing for release · M2 R8 off · M3 Emulator GMS noise · M4 Weak UIAutomator semantics · M5 Analyzer test noise (**fixed**) · L1 style infos · L2 shared applicationId  

---

## FIXED BUGS (summary)

| Fix | Outcome |
|-----|---------|
| FCM incomingLike | Functions compile + 78 tests green |
| Account settings test | PASS |
| Voice rules test | PASS |
| Integration smoke | PASS on emulator |
| Release registrant | Release APK PASS |

---

## AUTOMATED TEST RESULTS

See `AUTOMATED_TEST_RESULTS.md` — Flutter 654, Functions 78, Integration smoke PASS.

---

## MANUAL TEST RESULTS

See `MANUAL_TEST_RESULTS.md`. Proven on emulator: auth welcome (5 providers), release+debug cold start, Privacy Policy, prior Settings dump when session existed. Deep authenticated funnel not completed unattended.

---

## EMULATOR VS REAL DEVICE

See `EMULATOR_VS_REAL_DEVICE.md`. Real device **BLOCKED** this run; historical phone diffs noted as risk only.

---

## FIREBASE

| Service | Code/tests | Live this run |
|---------|------------|---------------|
| Auth | Strong widget/unit + bootstrap | Auth UI only |
| Firestore | Rules source tests PASS | Dual-user NOT TESTABLE |
| Storage | Rules tests PASS (E2EE blobs) | Upload E2E BLOCKED |
| Functions | 78 PASS + compile fix | Deploy not run |
| FCM | Types fixed | Delivery BLOCKED |
| App Check | Debug token / fallback in bootstrap | Dev smoke OK in integration |
| Security | Harden on `dd03fd1` | Live pen-test limited |

---

## PERFORMANCE

No 30–60 min soak. Short launches: skipped frames at cold start noted once; no ANR/FATAL in filtered samples.

---

## SECURITY

Prior harden present. No new CRITICAL security exploit proven. Do **not** claim App Store / KVKK compliance from this QA alone. Unauthorized cross-user access not live-probed beyond rules unit tests.

---

## RELEASE BLOCKERS

1. Physical dual-device messaging + hardware permissions  
2. Play signing + minify  
3. Deploy + smoke hardened backend  
4. Live account-delete on smoke users  
5. iOS path if shipping Apple  

---

## RECOMMENDED NEXT STEPS (morning)

1. Connect 2 phones; A/B chat text+image+voice  
2. Wire release keystore; Internal testing track  
3. Deploy functions+rules; `prepareSmokeTestUsers` funnel + cleanup  
4. Commit QA fixes (notifications + tests + smoke)  
5. Optional: soak + Crashlytics  

---

## Git delta from this QA (do not confuse with pre-existing WIP)

**QA-owned / relevant:** `functions/src/notifications.ts`, `functions/src/backend.ts`, account/voice/profile test fixes, `integration_test/smoke/app_launch_test.dart`, `qa/*` docs  

**Pre-existing dirty (preserved):** `firebase_bootstrap.dart`, pubspec/l10n, untracked automation admin, etc.

---

## MEVORA RELEASE READINESS

🔴 **NOT READY FOR RELEASE**
