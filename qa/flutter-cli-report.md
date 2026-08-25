# Flutter CLI Report — Mevora Multi-Emulator QA

**Date:** 2026-08-25  
**Branch:** `backup/wip-before-device-sync-20260824`  
**Flutter:** 3.41.9 · Dart 3.11.5  
**Firebase project (dev):** `mevora-d6ed0`  
**Firebase Emulator Suite:** Auth `:9099`, Firestore `:8080`, Storage `:9199` (UI `:4000`)

## CLI commands executed

| Command | Result |
|---------|--------|
| `flutter doctor -v` | PASS — no issues |
| `flutter --version` / `dart --version` | PASS |
| `flutter devices` | 3 Android emulators at peak (+ desktop/web) |
| `flutter emulators` | 1 broken AVD definition + 2 newly created |
| `adb devices` | emulator-5554 / 5556 / 5558 |
| `flutter analyze` | 2 info-only quote nits |
| `flutter test` | **654 PASS** (+ 2 new peer-name source tests PASS) |
| `npm test` (functions) | **78 PASS** |
| `flutter build apk --debug --flavor development` (live) | PASS |
| `flutter build apk --debug` with `USE_EMULATORS=true` + `USE_AUTH_EMULATOR=true` | PASS → `app-development-debug-emulators.apk` |
| `flutter build apk --release --flavor development` | PASS (existing artifact verified; cold start OK) |
| `flutter test integration_test/smoke/app_launch_test.dart` (emu + emulators) | FAIL/HANG under multi-emu load |
| `flutter test integration_test/smoke/multi_user_email_auth_test.dart` | HUNG after install (killed; device race with emu kill) |

## Environment notes

- Java not on PATH by default → Firebase emulators required `JAVA_HOME` = Android Studio JBR.
- Created AVDs: `Mevora_Emu_A` (medium_phone), `Mevora_Emu_B` (pixel_6) on API 37 Play image.
- Physical USB device: **none**.
- Firebase MCP was on wrong project; switched to `mevora-d6ed0` for tooling context.

## Artifacts

- Logs: `qa/analyze_run.log`, `qa/flutter_test_multi_run.log`, `qa/functions_test_multi_run.log`, `qa/integration_*.log`
- Screenshots: `build/qa-parity/multi-emu/`
- Seed/verify: `qa/multi_user_seed.json`, `qa/multi_user_verify.json`
- Tools: `tool/qa_multi_user_seed_admin.cjs`, `tool/qa_multi_user_verify.cjs`, `tool/qa_adb_email_login.ps1`
