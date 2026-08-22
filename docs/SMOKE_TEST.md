# Production Smoke Test

## Layers

| Layer | Location | Purpose |
|-------|----------|---------|
| Unit | `functions/test`, `test/` | Policies, filters, moderation |
| Integration | `firebase/tests/` | Rules + pipeline contracts |
| Backend smoke | `tools/smoke/` | Real Auth/Firestore/Storage state verification |
| Device E2E | `integration_test/smoke/` | App launch + UI shell |

## Smoke users

| Email | Purpose |
|-------|---------|
| `smoke-a@mevora.test` | User A |
| `smoke-b@mevora.test` | User B |

`users/{uid}.isSmokeTestUser` is server-only. Smoke users only discover other smoke users.

## Secrets

Set before deploy:

```powershell
firebase functions:secrets:set SMOKE_TEST_SECRET --project mevora-production
```

## Run backend smoke

```powershell
cd D:\Mevora\tools\smoke
npm install
$env:GOOGLE_APPLICATION_CREDENTIALS="path\to\service-account.json"
$env:SMOKE_FIREBASE_PROJECT="mevora-production"
node run_smoke_test.mjs
```

Emulator mode:

```powershell
$env:SMOKE_USE_EMULATOR="true"
node run_smoke_test.mjs
```

## Run device smoke

```powershell
cd D:\Mevora
flutter test integration_test/smoke/app_launch_test.dart
```

## Manual device checklist (production)

1. Register
2. Verify 18+ gate
3. Complete profile
4. Upload 3 photos and wait for processing
5. Open Discover
6. Match
7. Send message
8. Block / report
9. Delete account

## Output format

The smoke runner prints:

```text
MEVORA PRODUCTION SMOKE TEST
[1] Registration ...
...
FINAL RESULT: PASS / FAIL
Cleanup: PASS / FAIL
```
