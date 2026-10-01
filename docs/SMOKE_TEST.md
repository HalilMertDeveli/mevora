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

`users/{uid}.isSmokeTestUser` is server-only (clients cannot set or change it). Smoke users only
discover other smoke users, and members never see them.

### Passwords

Smoke users have **no fixed password**. Nothing in this repository can be used to sign in as one.

- `prepareSmokeTestUsers` generates a new random password for each user on every call and returns
  both in its response (`passwords.a`, `passwords.b`) to the caller who presented `SMOKE_TEST_SECRET`.
  They are not stored or logged anywhere else: keep the response if you need to sign in on a device,
  and call the function again if you lose it.
- Calling it again rotates both passwords and ends the users' open sessions, so a password from an
  earlier run stops working.
- The backend runner (`tools/smoke/`) works through the Admin SDK and never signs in. It gives the
  users it creates a random password that it does not keep.
- `cleanupSmokeTestUsers` deletes both users. Run it when a device session is finished.

After deploying a version that changes these functions, call `prepareSmokeTestUsers` once (or
`cleanupSmokeTestUsers`) so smoke users created by an older deploy get a new password.

## Secrets

Set before deploy:

```powershell
firebase functions:secrets:set SMOKE_TEST_SECRET --project mevora-production
```

Use a long random value (for example `node -e "console.log(require('crypto').randomBytes(32).toString('base64url'))"`)
and treat it like a credential: whoever holds it can create the smoke users and read their passwords.
Without a configured secret both smoke functions refuse every call (`smoke-secret-not-configured`);
a wrong or empty secret is refused with `smoke-secret-invalid`.

## Run backend smoke

From the repository root:

```powershell
cd tools\smoke
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
