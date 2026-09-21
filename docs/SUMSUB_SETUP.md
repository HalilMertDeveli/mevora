# Sumsub Profile Verification Setup

This guide covers sandbox setup for Mevora's Sumsub-powered profile verification.
**Never commit real credentials.** Use Firebase Functions secrets only.

## Overview

```
Flutter App
    ↓ (authenticated callable)
createSumsubAccessToken (Cloud Function)
    ↓ HMAC-signed API call
Sumsub API → access token
    ↓
Sumsub Flutter SDK (liveness + face match)
    ↓ webhook (authoritative)
sumsubWebhook (Cloud Function)
    ↓ Admin SDK
Firestore users/{uid}/verification/sumsub + users/{uid}.isVerified
    ↓ stream
Flutter UI (badge + status)
```

## 1. Sumsub account & sandbox

1. Create a Sumsub account at [sumsub.com](https://sumsub.com).
2. Switch Dashboard to **Sandbox** mode.
3. Create a verification level (e.g. `mevora-profile-verification`) with:
   - **Liveness** (recommended active level)
   - **Face match** / selfie step (per your level configuration)
4. Do **not** claim document/KYC features unless configured in the level.

## 2. App token & secret key

1. Dashboard → **Dev space** → **App Tokens** → **Generate app token**
2. Save (shown once):
   - `YOUR_SUMSUB_APP_TOKEN`
   - `YOUR_SUMSUB_SECRET_KEY`
3. Use **Sandbox** tokens only for development.

## 3. Webhook

1. Dashboard → **Webhooks** → **Webhook manager** → **Create webhook**
2. Target: your deployed function URL:
   ```
   https://europe-west1-<PROJECT_ID>.cloudfunctions.net/sumsubWebhook
   ```
3. Types: at minimum `applicantReviewed`, `applicantPending`, `applicantCreated`
4. Signature: **HMAC_SHA256_HEX**
5. Save webhook secret as `YOUR_SUMSUB_WEBHOOK_SECRET`

## 4. Firebase Functions secrets

```bash
firebase functions:secrets:set SUMSUB_APP_TOKEN
firebase functions:secrets:set SUMSUB_SECRET_KEY
firebase functions:secrets:set SUMSUB_WEBHOOK_SECRET
```

Optional level name param (default: `mevora-profile-verification`):

```bash
firebase functions:params:set SUMSUB_LEVEL_NAME=mevora-profile-verification
```

Deploy:

```bash
cd functions && npm run build
firebase deploy --only functions:createSumsubAccessToken,functions:sumsubWebhook
```

## 5. Firestore schema

Path: `users/{uid}/verification/sumsub`

| Field | Writer | Description |
| --- | --- | --- |
| `verificationStatus` | Functions only | `not_started`, `started`, `pending`, `approved`, `rejected`, `retry_required` |
| `verificationLevel` | Functions | Sumsub level name |
| `sumsubApplicantId` | Functions | Sumsub applicant ID |
| `verificationUpdatedAt` | Functions | Last status change |
| `verifiedAt` | Functions | Set on approval |
| `verificationAttemptCount` | Functions | Rate limit counter |
| `lastVerificationAttemptAt` | Functions | Cooldown anchor |

Account flag: `users/{uid}.isVerified` — **Functions/webhook only**. Clients cannot write it.

## 6. Security rules

- `users/{uid}.isVerified` — blocked on client create/update (existing rules)
- `users/{uid}/verification/{docId}` — owner read, **no client writes**

## 7. Flutter SDK

Dependency: `flutter_idensic_mobile_sdk_plugin: ^1.45.1`

The app calls `createSumsubAccessToken`, launches `SNSMobileSDK`, and listens to Firestore for status.
SDK completion does **not** set verified state — webhook does.

## 8. Testing checklist (sandbox)

Without credentials, UI and backend compile but token generation returns `verification-not-configured`.

With credentials:

- [ ] Authenticated user opens Profile → Verify
- [ ] `createSumsubAccessToken` returns token (check Functions logs)
- [ ] Sumsub SDK opens liveness flow
- [ ] Webhook received and digest validated
- [ ] Firestore status updates to `pending` then `approved`
- [ ] `users/{uid}.isVerified == true`
- [ ] Badge appears on profile / discovery
- [ ] Client cannot write `isVerified: true` (rules reject)
- [ ] Duplicate webhook is idempotent
- [ ] Cooldown blocks rapid retries
- [ ] Account deletion removes `verification/sumsub`

## 9. Production migration

1. Create **Production** app token + secret in Sumsub Dashboard
2. Configure production verification level (mirror sandbox steps)
3. Set production secrets in Firebase
4. Register production webhook URL
5. Test with a real device before release
6. Monitor webhook logs and failed digest events

## Environment placeholders

| Variable | Example placeholder | Notes |
| --- | --- | --- |
| `SUMSUB_APP_TOKEN` | `YOUR_SUMSUB_APP_TOKEN` | Secret — sandbox or production token |
| `SUMSUB_SECRET_KEY` | `YOUR_SUMSUB_SECRET_KEY` | Secret — API signing |
| `SUMSUB_WEBHOOK_SECRET` | `YOUR_SUMSUB_WEBHOOK_SECRET` | Secret — webhook digest |
| `SUMSUB_LEVEL_NAME` | `YOUR_SUMSUB_LEVEL` | Param — verification level name |
| `SUMSUB_ENVIRONMENT` | `sandbox` or `production` | Param — metadata only; token selects mode |
| `SUMSUB_BASE_URL` | `https://api.sumsub.com` | Param — same host for both modes |

Set secrets per Firebase project (dev/staging/production). Never commit values to git.

## Age verification (future)

Mevora enforces 18+ at onboarding via `birthDate` (`MIN_ONBOARDING_AGE = 18` in `profileSafety.ts`).
Sumsub profile verification currently covers liveness + face match only.
If a Sumsub level adds document-based age checks, wire results through the same webhook
→ `users/{uid}/verification/sumsub` path. Do not expose age claims in UI until configured.

## Account deletion & Sumsub applicant lifecycle

`deleteUserAccount` removes `users/{uid}/verification/sumsub` from Firestore and then
cleans up the Sumsub side through `sumsubApplicantLifecycle.ts`, using the two operations
Sumsub publishes:

| Step | Call | Effect |
|---|---|---|
| 1 | `POST /resources/applicants/{applicantId}/reset` | Clears the collected verification data; the applicant returns to its initial state. Responds `{"ok": 1}`. |
| 2 | `PATCH /resources/applicants/{applicantId}/presence/deactivated` | The profile behaves as if it never existed: no operator can act on it and it is ignored for duplicate checks. |

Behaviour contract (see `functions/test/sumsubApplicantLifecycle.test.cjs`):

- No applicant id, or credentials not configured → no call is made.
- An applicant id that is not 24 alphanumeric characters is refused before it can reach a
  request path.
- `400` / `404` from Sumsub means the applicant is already gone and counts as success, so
  re-running deletion is safe.
- Sumsub refuses deactivation while the review status is `pending`, `queued` or
  `prechecked`. The reset has already cleared the data at that point, so the outcome is
  logged as `reset-only` and account deletion continues.
- Nothing here ever throws. Account deletion must not fail because an external applicant is
  missing, mid-review, or because Sumsub is unreachable.
- Logs carry the uid and an outcome only — never the applicant id or a response body, both
  of which can carry KYC identifiers.

`deleteUserAccount` binds `SUMSUB_APP_TOKEN` and `SUMSUB_SECRET_KEY` (not the webhook
secret) so these calls can be signed. Without those secrets the cleanup is a logged no-op.

### External blocker — permanent erasure

Sumsub publishes no API for permanently erasing an applicant. Deactivation is reversible and
the record stays in Sumsub's database. A GDPR erasure request must be raised with Sumsub
support out of band; it cannot be automated from Cloud Functions. Decide and document the
retention position with Sumsub before production launch.

## MEVORA SUMSUB ACTIVATION CHECKLIST

Use this checklist when credentials arrive. Do not skip security steps.

### Sumsub Dashboard
- [ ] Create Sandbox account and switch Dashboard to Sandbox mode
- [ ] Create verification level with Liveness + Face Match steps
- [ ] Generate Sandbox App Token + Secret Key (save once)
- [ ] Create webhook pointing to `sumsubWebhook` URL
- [ ] Set webhook signature to HMAC_SHA256_HEX and save webhook secret
- [ ] Enable webhook types: `applicantCreated`, `applicantPending`, `applicantReviewed`

### Firebase (per project: dev / staging / production)
- [ ] `firebase functions:secrets:set SUMSUB_APP_TOKEN`
- [ ] `firebase functions:secrets:set SUMSUB_SECRET_KEY`
- [ ] `firebase functions:secrets:set SUMSUB_WEBHOOK_SECRET`
- [ ] Set `SUMSUB_LEVEL_NAME` param to your level name
- [ ] Set `SUMSUB_ENVIRONMENT=sandbox` (switch to `production` for prod project)
- [ ] Deploy `createSumsubAccessToken` and `sumsubWebhook`
- [ ] Register App Check debug tokens for dev devices

### End-to-end sandbox test
- [ ] Sign in with Firebase Auth test user
- [ ] Profile → Verify your profile → Start verification
- [ ] Callable returns token (not `verification-not-configured`)
- [ ] Sumsub SDK opens on physical device
- [ ] Complete liveness / face match in Sandbox
- [ ] Webhook received with valid digest (Functions logs)
- [ ] Firestore `verificationStatus` → `pending` → `approved`
- [ ] `users/{uid}.isVerified == true` (server-set only)
- [ ] Verified badge on Profile, Discovery, Matches
- [ ] Client write to `isVerified` rejected by rules
- [ ] Duplicate webhook does not corrupt state
- [ ] Cooldown blocks rapid re-attempts
- [ ] Account deletion removes verification doc

### Production cutover
- [ ] Create Production App Token + Secret in Sumsub Dashboard
- [ ] Mirror verification level configuration
- [ ] Set production secrets on production Firebase project
- [ ] Set `SUMSUB_ENVIRONMENT=production`
- [ ] Update webhook URL for production Functions
- [ ] Run one real-device verification before release
- [ ] Monitor webhook failures and digest mismatches

### Without credentials (current state)
- UI, routes, Firestore rules, and Functions compile and deploy
- `createSumsubAccessToken` returns `failed-precondition` / `verification-not-configured`
- Flutter shows: **"Verification is temporarily unavailable."**
- No live Sandbox test has been performed
