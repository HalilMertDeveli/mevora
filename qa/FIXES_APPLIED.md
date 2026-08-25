# Fixes Applied During Full QA (2026-08-25)

| ID | File(s) | Change | Why | Verification |
|----|---------|--------|-----|--------------|
| C1 | `functions/src/notifications.ts`, `functions/src/backend.ts` | Added `incomingLike` FCM type + TR/EN copy; route `/likes-you`; prefer `matchNotifications`; removed invalid `idempotencyKey` | Unblock Cloud Functions TypeScript build / deploy | `npm test` → 78/78 PASS |
| H1 | `test/features/authentication/account_settings_page_test.dart` | Larger surface + `ensureVisible` before delete tap | Export data UI pushed delete off-screen in widget test | Test PASS |
| H2 | `test/features/chat/chat_voice_rules_test.dart` | Expect encrypted chat blob Storage rules; keep client audio allowlist assertions | Align tests with fail-closed E2EE storage policy | Test PASS |
| M5 | `test/features/settings/profile_answers_page_test.dart` | Remove unused named `delay` noise | Analyzer warning | Cleaner analyze |
| H5 | `integration_test/smoke/app_launch_test.dart` | Bootstrap `AppEnvironment.development`; assert `MaterialApp`; avoid brittle `pumpAndSettle` | Prior smoke used production env on development flavor → empty tree | Emulator integration PASS |
| C2 | Regenerated `android/.../GeneratedPluginRegistrant.java` via `flutter pub get` after deleting polluted registrant | Remove `integration_test` plugin from release classpath | `flutter build apk --release --flavor development` SUCCESS; release cold start → auth UI |

## Intentionally not changed

- Matching algorithm, question catalog, UI redesign  
- Production data / smoke user cleanup via live callables (secret-gated; not invoked)  
- Account delete on any real/persisted emulator session  
- Force-push / hard reset  
- Untracked automation admin WIP left as-is  

## Pre-existing WIP preserved (not introduced by QA)

- `lib/core/services/firebase/firebase_bootstrap.dart` modifications already in tree  
- `pubspec.yaml` / l10n / automation admin untracked files  
- Branch tip before QA fixes: `dd03fd1`  
