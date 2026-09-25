# Didit identity verification — sandbox QA runbook

Everything below is already set up. This is what to do when you sit down to
test, and what to look for.

---

## What is already done

| | |
|---|---|
| Didit sandbox app | MEVORA (Sandbox), Test mode on |
| Workflow | `b618b6f8-e93f-442d-8e0b-355d29f1d376` — ID Verification + Passive Liveness + Face Match 1:1 + Device & IP |
| Secrets (`mevora-d6ed0`) | `DIDIT_API_KEY` v2, `DIDIT_WEBHOOK_SECRET` v2 |
| Functions (europe-west1) | `createIdentityVerificationSession`, `getIdentityVerificationState`, `identityVerificationWebhook` |
| Webhook destination | `https://europe-west1-mevora-d6ed0.cloudfunctions.net/identityVerificationWebhook`, `status.updated` only |
| Proven | A real Didit webhook passed signature, freshness, event-type and correlation checks, then was correctly refused with `no_such_user` |
| QA account | `didit.qa@mevora.test` — uid `ZKuuyBl0pEb2MBmILUcOe45AR9H2`. Password is not in the repo; it is in the team password store, or reset it from the Firebase console. |

## Why this runs against the real backend, not the Emulator Suite

The usual two-user QA points the app at the Firebase Emulator Suite. That
cannot work here: Didit's webhook has to reach a public URL, and localhost is
not one. So this flow runs against **mevora-d6ed0** — which is the project the
`development` flavor already targets, and where the Didit functions and secrets
live.

`mevora-d6ed0` holds the real user data (129 accounts). `mevora-production` is
empty and unused. So treat mevora-d6ed0 as live data even though the flavor is
called development: use the QA account above, not a real one.

## Launch — physical device

Preferred: the camera is real, so document capture and the selfie behave the
way they will for users. Sandbox still mocks the *analysis*, so the outcome
stays deterministic either way — what a real device buys you is a truthful
read on the UX.

1. Enable Developer options → USB debugging on the phone, plug it in, accept
   the RSA prompt.
2. Confirm it is seen:
   ```powershell
   & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices -l
   ```
3. Build and install:
   ```powershell
   cd D:\Mevora-deploy
   .\tool\flutter_install_android.ps1 -UninstallFirst -GrantPermissions
   ```

That script already does the right thing: `development` flavor,
`USE_EMULATORS=false` so it talks to the deployed backend, and it reads the App
Check debug token from `tool/app_check_debug_token.local` — without that token
every callable comes back rejected. It prefers a physical device when an
emulator is also attached, so no `-DeviceId` is needed.

`-GrantPermissions` pre-grants camera, location, notifications and media so the
first run does not stall on system dialogs.

The App Check debug token is a fixed value already registered in the Firebase
console, so a brand-new device works without registering anything — as long as
the dart-define reaches the build, which the script handles.

## Launch — emulator (fallback)

`Mevora_Emu_A` and `Mevora_Emu_B` are configured and the APK is already
installed on both.

```powershell
cd D:\Mevora-deploy
.\tool\flutter_run_dev.ps1 -DeviceId emulator-5554
```

The emulated camera shows a synthetic scene. Good enough to prove the plumbing,
useless as an anti-spoofing test.

`adb.exe` is not on PATH; it lives at
`%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`.

## The happy path

1. Sign in with the QA account (Sign in with email).
2. Profile → the verification tile → **Verify your profile**.
3. Tap start. Chrome opens Didit's hosted flow.
4. Work through document capture → selfie → face match. Any ID will do, and on
   an emulator a synthetic scene is fine: sandbox mocks every provider, so
   nothing you photograph is really analysed and the outcome is deterministic.
   **Do not use a real identity document** — there is no reason to, and the
   images leave the device.
5. Finish. Didit sends you back to `mevora://verify/identity`, which reopens
   Mevora.
6. The screen should show a processing state, then become verified once the
   webhook lands.

**The point of the test is step 6.** The badge must appear only after the
backend says so — never on the strength of the deep link.

## What to check, and where

Firestore, `users/{uid}/verification/identity`:

```
status        pending → in_progress → verified
provider      didit
providerSessionId   <the Didit session>
verifiedAt    set only at the end
```

and `users/{uid}.isVerified` plus `profiles/{uid}.isVerified` both true, both
written by the same transaction.

Function logs:

```powershell
gcloud logging read 'resource.labels.service_name="identityverificationwebhook" AND jsonPayload.message:"identity"' `
  --project=mevora-d6ed0 --limit=20 --freshness=1h `
  --format="value(timestamp,severity,jsonPayload.message,jsonPayload.skipped,jsonPayload.uid,jsonPayload.status)"
```

Expected on success: `identity verification state updated` with `status=verified`.

Anything of the form `identity webhook rejected` with a reason
(`missing_signature`, `stale_timestamp`, `invalid_signature`,
`missing_correlation`) means the delivery never got past authentication.

## Cases worth exercising after the happy path

| Case | How | Expected |
|---|---|---|
| Cancel mid-flow | Close Chrome, return to Mevora | Stays unverified, processing state, retry available |
| App killed mid-flow | `adb -s <cihaz> shell am force-stop com.mevora.app`, reopen | Resume reads backend state, shows whatever actually happened |
| Deep link is not proof | `adb -s <cihaz> shell am start -a android.intent.action.VIEW -d "mevora://verify/identity?status=Approved"` while unverified | Mevora opens and refreshes; **must not** become verified |
| Second tap | Tap start twice quickly | One session only; backend returns the in-flight one |
| Retry after decline | Use a `decline_*` sandbox scenario | Declined with a reason-specific message; retry blocked for 15 min |
| Two users | Sign in as another account on a second device or Emu B | Cannot read or affect the first user's verification state |

The third row is the one that matters most — it is the whole security claim of
the Flutter layer, and it is cheap to check.

## Driving deterministic outcomes

The app does not send `sandbox_scenario`, so a session started from the app
follows the workflow's default. To force a specific outcome, create the session
directly instead:

```powershell
$key = (& gcloud.cmd secrets versions access latest --secret=DIDIT_API_KEY --project=mevora-d6ed0)
$r = Invoke-RestMethod -Uri "https://verification.didit.me/v3/session/" -Method Post `
     -Headers @{ "x-api-key"=$key; "Content-Type"="application/json" } `
     -Body '{"workflow_id":"b618b6f8-e93f-442d-8e0b-355d29f1d376","vendor_data":"ZKuuyBl0pEb2MBmILUcOe45AR9H2","sandbox_scenario":"decline_face_match_low_similarity"}'
$r | Select-Object session_id, status, environment, url
```

`vendor_data` must be the QA account's uid or the webhook will be refused with
`no_such_user`. Useful scenarios: `approve`,
`decline_face_match_low_similarity`, `decline_liveness_attack`,
`decline_could_not_recognize_document`, `review_face_match_borderline`.

## Cleaning up afterwards

The QA account is a real account in mevora-d6ed0. When finished, delete it
through the app (Settings → delete account) — that also exercises the Phase 5
erasure path, which is worth doing deliberately at least once. Then check that
`users/{uid}/verification/identity` is gone and either the Didit session was
erased or `identityErasurePending/{uid}` exists with a job behind it.

## Known limits

- Passive Liveness against an emulated camera is a plumbing test, not a real
  anti-spoofing test. Sandbox mocks the provider either way.
- `sandbox_scenario` is rejected on live applications, so none of this can
  accidentally run against production.
- Nothing here has been tested on iOS. The deep link is registered
  (`CFBundleURLSchemes` already contains `mevora`), but no iOS run was made.
