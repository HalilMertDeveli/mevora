# Bugs Found — Mevora Full QA (2026-08-25)

## CRITICAL

### C1 — Cloud Functions compile break: missing `incomingLike` FCM types
- **Feature:** Notifications / Discover like push  
- **Steps:** `cd functions && npm run build` (or any deploy that compiles TS)  
- **Expected:** Clean compile  
- **Actual:** `FcmTypes.incomingLike` / `likeNotifications` missing; `idempotencyKey` arg invalid  
- **Root Cause:** `backend.ts` wired incoming-like push without completing `notifications.ts` API  
- **Fixed:** YES (`functions/src/notifications.ts`, `backend.ts`)  
- **Regression:** `npm test` → 78/78 PASS  

### C2 — Release APK fails: `integration_test` in `GeneratedPluginRegistrant`
- **Feature:** Android release packaging  
- **Steps:** `flutter build apk --release --flavor development`  
- **Expected:** APK produced  
- **Actual:** `package dev.flutter.plugins.integration_test does not exist`  
- **Root Cause:** Dev/integration tooling polluted Android plugin registrant  
- **Fixed:** YES — delete registrant + `flutter pub get` regenerates clean registrant; release APK built (`app-development-release.apk` ~143–150MB)  
- **Regression:** Release install + cold start on emulator → auth welcome screen  

## HIGH

### H1 — Widget test: Account Settings delete button not hittable after export UI
- **Feature:** Account settings / CI  
- **Expected:** Delete Account tap succeeds in test  
- **Actual:** Off-screen after “export my data” row added  
- **Fixed:** YES — larger surface + `ensureVisible`  
- **Regression:** `account_settings_page_test` PASS  

### H2 — Voice Storage rules unit test outdated vs E2EE encrypted-only uploads
- **Feature:** Chat voice / Storage rules tests  
- **Expected:** Tests match current encrypted blob rules  
- **Actual:** Expected plaintext `audio/*` MIME allowlist  
- **Fixed:** YES — test updated for encrypted octet-stream  
- **Regression:** `chat_voice_rules_test` PASS  

### H3 — Physical Android device unavailable during this QA window
- **Feature:** Real-device E2E (camera/mic/FCM/keyboard)  
- **Status:** BLOCKED — only `emulator-5554` present (`adb devices`)  
- **Impact:** Cannot clear dual-user chat/voice/image, kill-state FCM, or Play Integrity paths  

### H4 — Live Firebase deploy of hardened rules/functions not verified in this run
- **Feature:** Security / matching / deleteAccount / App Check callables  
- **Status:** Code on branch `dd03fd1` + QA fixes; production/project smoke deploy not executed here  
- **Impact:** Client fail-closed E2EE + rules may diverge from undeployed backend  

### H5 — Integration smoke historically asserted empty tree (`find.byType(Object)`) under mismatched env
- **Feature:** `integration_test/smoke/app_launch_test.dart`  
- **Actual:** FAIL with 0 widgets when bootstrapping production env on development flavor  
- **Fixed:** YES — development bootstrap + `MaterialApp` assertion  
- **Regression:** PASS on emulator  

### H6 — Debug APK installed via integration_test left package without launcher activities until reinstall
- **Feature:** Emulator install hygiene  
- **Actual:** After failed/partial integration install, `monkey` reported no activities; reinstall fixed  
- **Status:** Observed; mitigated by reinstalling debug/release APKs  

## MEDIUM

### M1 — Release signing still debug keystore
- **File:** `android/app/build.gradle.kts` (`signingConfig = debug` + TODO)  
- **Impact:** Cannot ship Play Store release as-is  

### M2 — R8 / minify not enabled for release  
- **Impact:** Larger APK, weaker obfuscation  

### M3 — Emulator Google Play Services noise (`SecurityException: Unknown calling package name 'com.google.android.gms'`)
- **Impact:** May affect Google Sign-In / Play Integrity on emulator; not a FATAL Flutter crash in samples  

### M4 — Fragile Flutter semantics for UIAutomator (many buttons lack stable text/content-desc matching)
- **Impact:** Unattended deep UI automation incomplete; coordinate taps hit legal footer / system Phone  

### M5 — Analyzer unused named parameter in `profile_answers_page_test`
- **Fixed:** YES  

## LOW

### L1 — Prefer double quotes infos in security tests (style only)  
### L2 — Development/production share `applicationId` `com.mevora.app` (intentional for SHA) — install overwrite risk  

## NOT BUGS / NOTES

- Auth welcome shows Google / Apple / Phone / Spotify / Email — expected.  
- Privacy Policy screen reachable from auth legal footer — PASS (manual).  
- Prior session on emulator had persisted login as developer account; later reinstalls returned to logged-out auth gate (session not treated as production user data to modify/delete).  
