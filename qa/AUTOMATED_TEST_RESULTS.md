# Automated Test Results

**Date:** 2026-08-25  
**Host:** Windows 11 / Flutter 3.41.9  
**Branch:** `backup/wip-before-device-sync-20260824`

## Flutter (`flutter test`)

| Metric | Value |
|--------|-------|
| Final run | **654 passed, 0 failed** |
| Log | `qa/flutter_test_run.log` |
| Initial pre-fix failures | 2 (`account_settings_page_test`, `chat_voice_rules_test`) — fixed then green |

Coverage areas exercised by suite (non-exhaustive): auth widgets, chat/E2EE fail-closed, matching gates, relationship Q&A, discovery ranking, security rules source tests, settings, animations, shared widgets.

## Integration (`flutter test integration_test/...`)

| Test | Device | Result |
|------|--------|--------|
| `smoke/app_launch_test.dart` (before fix) | emulator-5554 | FAIL (empty tree / wrong env) |
| `smoke/app_launch_test.dart` (after fix) | emulator-5554 | **PASS** |
| Log | `qa/integration_smoke_run.log` | |

## Cloud Functions (`npm test`)

| Metric | Value |
|--------|-------|
| Result | **78 passed, 0 failed** |
| Suites | 21 |
| Note | PowerShell blocks `npm.ps1`; run via `cmd /c npm test` |
| Log | `qa/functions_test_run.log` |

## Static analysis

| Command | Result |
|---------|--------|
| `flutter analyze` (full) | Exit non-zero historically for warnings/infos; no compile-blocking errors in product paths after QA test fixes. Re-check latest run in terminal snapshot. |

## Build automation

| Command | Result |
|---------|--------|
| `flutter build apk --debug --flavor development` | PASS |
| `flutter build apk --release --flavor development` | FAIL → PASS after plugin registrant regen |

## Gaps (automated coverage still thin)

1. Dual-user messaging E2E  
2. Live Storage upload/download integration  
3. Account deletion live callable  
4. Phone OTP / Google / Spotify full auth  
5. Matching score golden tests vs live CF  
6. FCM delivery  
7. Network-offline widget/integration suites  

Recommended next automated additions (safe, architecture-aligned): expand repository fakes for chat send fail-closed; account-delete orchestration unit tests; matching score pure-function goldens (if not already complete).  
