# Smoke Test (emulator only)

The smoke surface exists in the repository and in the Firebase emulator suite, and nowhere else.
A deployed backend does not export the smoke callables, does not need `SMOKE_TEST_SECRET`, and
gives a smoke-flagged account no fast path through photo moderation. The backend runner refuses
to start unless every service it writes to is an emulator on this machine.

## Layers

| Layer | Location | Purpose |
|-------|----------|---------|
| Unit | `functions/test`, `test/` | Policies, filters, moderation |
| Integration | `firebase/tests/` | Rules + pipeline contracts |
| Backend smoke | `tools/smoke/` | Auth/Firestore/Storage state verification against the emulator suite |
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

- `prepareSmokeTestUsers` (emulator only) generates a new random password for each user on every call and returns
  both in its response (`passwords.a`, `passwords.b`) to the caller who presented `SMOKE_TEST_SECRET`.
  They are not stored or logged anywhere else: keep the response if you need to sign in on a device,
  and call the function again if you lose it.
- Calling it again rotates both passwords and ends the users' open sessions, so a password from an
  earlier run stops working.
- The backend runner (`tools/smoke/`) works through the Admin SDK and never signs in. It gives the
  users it creates a random password that it does not keep.
- `cleanupSmokeTestUsers` (emulator only) deletes both users. Run it when a device session is
  finished.

Both callables refuse with `emulator-only` outside the Functions emulator, whatever secret is
presented. Smoke users an older deploy left in a live project cannot be rotated by this code any
more: delete those accounts (`docs/DEPLOY_NOTES.md` → "Emulator-only callables").

## Secrets

`SMOKE_TEST_SECRET` is an emulator value only — there is nothing to set before a deploy. Put it
in `functions/.secret.local` (not committed):

```text
SMOKE_TEST_SECRET=<long random value>
```

Use a long random value (for example `node -e "console.log(require('crypto').randomBytes(32).toString('base64url'))"`)
and treat it like a credential: whoever holds it can create the smoke users and read their passwords.
Without a configured secret both smoke functions refuse every call (`smoke-secret-not-configured`);
a wrong or empty secret is refused with `smoke-secret-invalid`.

## Run backend smoke

With the emulator suite running (Auth, Firestore, Storage, Functions), from the repository root:

```powershell
cd tools\smoke
npm install
$env:SMOKE_USE_EMULATOR="true"
$env:SMOKE_FIREBASE_PROJECT="<the project id the emulator suite runs as>"
$env:FIRESTORE_EMULATOR_HOST="127.0.0.1:8080"
$env:FIREBASE_AUTH_EMULATOR_HOST="127.0.0.1:9099"
$env:FIREBASE_STORAGE_EMULATOR_HOST="127.0.0.1:9199"
node run_smoke_test.mjs
```

The runner exits with a list of what is missing unless `SMOKE_USE_EMULATOR` is `true`, all three
emulator hosts are loopback addresses and a project is named. There is no production mode and no
default project.

## Run device smoke

```powershell
cd D:\Mevora
flutter test integration_test/smoke/app_launch_test.dart
```

## Manual device checklist

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
MEVORA SMOKE TEST
[1] Registration ...
...
FINAL RESULT: PASS / FAIL
Cleanup: PASS / FAIL
```
