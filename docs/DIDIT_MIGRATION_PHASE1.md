# Didit Identity Verification — Phase 1: Audit & Migration Foundation

Base: `origin/main` @ `95e38d68b903e3a0ead5f46fd80b95611b106eda`
Branch: `feature/didit-identity-verification`
Scope: audit + design + provider-neutral foundation. **No Didit call is wired,
no production behaviour changes, nothing is deployed.**

---

## 1. Current Sumsub architecture (STEP 2)

`grep -ril sumsub` over source (excluding `functions/lib/` build output, docs and
agent scratch) returns **21 source files**: 12 backend TypeScript, 3 Flutter, 1
pubspec dependency, plus Firestore rules comments and docs.

| Component | File | Purpose | Used by | Data stored | Security role | Migration action |
|---|---|---|---|---|---|---|
| Credential config | `functions/src/sumsub/sumsubConfig.ts` | Resolves `SUMSUB_APP_TOKEN` / `SUMSUB_SECRET_KEY` / `SUMSUB_WEBHOOK_SECRET` from Secret Manager; level name, env, base URL | token callable, webhook | — | **Server-only secrets.** Correct today | REPLACE WITH DIDIT |
| Request signing | `functions/src/sumsub/sumsubAuth.ts` | `HMAC-SHA256(secret, ts+METHOD+path+body)`; webhook digest verify with timing-safe compare | client, webhook | — | Signature authority | REPLACE WITH DIDIT (Didit uses a static `x-api-key`, not per-request signing) |
| HTTP client | `functions/src/sumsub/sumsubClient.ts` | `POST /resources/accessTokens/sdk`, generic signed request | token callable | — | Holds credentials in memory only | REPLACE WITH DIDIT |
| Session start | `functions/src/sumsub/createSumsubAccessToken.ts` | Callable; auth + App Check; gates; returns short-lived SDK token | Flutter `VerificationController` | writes attempt counters | **uid comes from `request.auth.uid` only** — correct | REPLACE WITH DIDIT (`createIdentityVerificationSession`) |
| Doc model + gates | `functions/src/sumsub/sumsubVerification.ts` | `users/{uid}/verification/sumsub`, 15-min cooldown, 5 attempts/day | callable, webhook | status, applicantId, attempt counters | Abuse limiter | RENAME TO PROVIDER-NEUTRAL (gates are provider-agnostic; keep the logic, drop the name) |
| Status mapping | `functions/src/sumsub/sumsubStatus.ts` | Sumsub review answers → internal status | webhook | — | Decides `approved` | RENAME TO PROVIDER-NEUTRAL (superseded by `functions/src/identity/`) |
| Webhook | `functions/src/sumsub/sumsubWebhook.ts` | Verifies `x-payload-digest`, maps status, writes verification doc **and `users/{uid}.isVerified`** | Sumsub | verification doc + badge flag | **The single verified authority** | REPLACE WITH DIDIT |
| Applicant deletion | `functions/src/sumsub/sumsubApplicantLifecycle.ts` | **Stub** — 17 lines, `TODO(sumsub-activation)`, returns without calling anything | `deleteAccount.ts` | — | Provider-side erasure — **not implemented in `main`** | REPLACE WITH DIDIT |
| Barrel | `functions/src/sumsub/index.ts` | Re-exports | `functions/src/index.ts` | — | — | REPLACE WITH DIDIT |
| Function exports | `functions/src/index.ts:31` | `export {createSumsubAccessToken, sumsubWebhook}` | Firebase deploy | — | Public surface | REPLACE WITH DIDIT |
| Deletion hook | `functions/src/deleteAccount.ts` | Reads `sumsubApplicantId`, deletes the verification doc, calls the stub | account deletion | — | Erasure path | REPLACE WITH DIDIT |
| Admin read | `functions/src/backend.ts:692` | Admin reads `users/{uid}/verification/sumsub`; comment says "No Sumsub applicant secrets" | admin console | — | Read-only projection | RENAME TO PROVIDER-NEUTRAL |
| Flutter SDK | `pubspec.yaml:22` `flutter_idensic_mobile_sdk_plugin: ^1.45.1` | Sumsub mobile SDK | `VerificationController` | — | Client capture only | REMOVE (replace with `didit_sdk`) |
| Flutter domain | `lib/features/verification/domain/entities/profile_verification.dart` | `ProfileVerificationStatus`, `sumsubApplicantId` field | controller, screens, badge | — | UI state | RENAME TO PROVIDER-NEUTRAL |
| Flutter data source | `lib/.../firebase_verification_data_source.dart` | Reads `users/$uid/verification/sumsub`; invokes `createSumsubAccessToken` | repository | — | Read-only | REPLACE WITH DIDIT |
| Flutter controller | `lib/.../verification_controller.dart` | `SNSMobileSDK.init(...).launch()` + token refresh | verify screen | — | **Does not trust the SDK result** — correct | REPLACE WITH DIDIT |
| Discovery entity | `lib/features/discovery/domain/entities/discovery_candidate.dart` | Comment only | — | — | — | UNRELATED |
| Firestore rules | `firebase/firestore.rules` | Comments name Sumsub; `verification/{docId}` is read-owner / write-never | — | — | Correct | RENAME TO PROVIDER-NEUTRAL (comments only) |
| Secrets | Secret Manager: `SUMSUB_APP_TOKEN`, `SUMSUB_SECRET_KEY`, `SUMSUB_WEBHOOK_SECRET` | Exist in `mevora-d6ed0` | callable, webhook | — | — | PRESERVE TEMPORARILY (do not delete in Phase 1) |

## 2. Verified authority (STEP 3)

```
Sumsub webhook (signed)
  → mapSumsubToVerificationStatus → "approved"
  → tx writes users/{uid}/verification/sumsub.verificationStatus
  → tx writes users/{uid}.isVerified = true          ← AUTHORITATIVE
  → UserDocument.isVerified → AuthUser.isVerified
  → profile tab / settings / VerifiedProfileBadge
  → discovery: profiles[isVerified] || users[isVerified]
  → matches: social.ts profilePreview reads users.isVerified
```

**CURRENT AUTHORITATIVE VERIFIED FIELD:** `users/{uid}.isVerified` (boolean),
mirrored per-surface but never independently decided.

**CLIENT CAN SELF-VERIFY: NO.** Verified by rule reading:

- `users/{uid}` create: `isVerified` is in the create allowlist but pinned —
  `request.resource.data.get('isVerified', false) == false` (rules:361).
- `users/{uid}` update: `isVerified` is **absent** from `userUpdateKeysAllowed()`
  and additionally pinned to its prior value (rules:387-388).
- `profiles/{uid}`: `isVerified` is in neither `profileCreateKeysAllowed()` nor
  `profileUpdateKeysAllowed()`, and `profileLifecycleClientSafe()` /
  `profileLifecycleUpdateSafe()` deny it explicitly.
- `users/{uid}/verification/{docId}`: `allow read: if isOwner(userId);`
  `allow create, update, delete: if false;` (rules:565-568).

No security defect found in the current verified authority.

**Reported separately, not fixed (out of scope):**
`lib/features/discovery/data/repositories/discovery_repository_impl.dart:191`
reads `profiles['isVerified'] == true || raw['isVerified'] == true`, but no
backend writer ever sets `profiles/{uid}.isVerified` — only `users/{uid}`. The
`profiles` half of that `||` is dead. Not exploitable (both fields are
server-only), but it is a misleading second source of truth. Phase 2 collapses
it to the single field.

## 3. Data model (STEP 4)

Document: `users/{uid}/verification/sumsub`

| Field | Classification |
|---|---|
| `verificationStatus` | PROVIDER-NEUTRAL (values are Sumsub-shaped) · SERVER-ONLY |
| `verificationLevel` | PROVIDER-SPECIFIC (Sumsub level name) · SERVER-ONLY |
| `sumsubApplicantId` | PROVIDER-SPECIFIC · SENSITIVE (provider correlation id) · SERVER-ONLY |
| `verificationUpdatedAt` | PROVIDER-NEUTRAL · SERVER-ONLY |
| `verifiedAt` | PROVIDER-NEUTRAL · SERVER-ONLY |
| `verificationAttemptCount` | PROVIDER-NEUTRAL (abuse gate) · SERVER-ONLY |
| `lastVerificationAttemptAt` | PROVIDER-NEUTRAL · SERVER-ONLY |
| `lastWebhookType` | PROVIDER-SPECIFIC · SERVER-ONLY |
| `lastWebhookAt` | PROVIDER-NEUTRAL · SERVER-ONLY |
| `lastWebhookCorrelationId` | PROVIDER-SPECIFIC (idempotency key) · SERVER-ONLY |
| `users/{uid}.isVerified` | PROVIDER-NEUTRAL · SERVER-ONLY · the badge authority |

No document image, selfie, liveness video, ID number or raw webhook payload is
stored anywhere. That property must be preserved.

## 4. Didit target architecture (STEPS 7-11)

Verified against current official docs (September 2026).

**Session creation** — `POST https://verification.didit.me/v3/session/`,
header `x-api-key`. Body: `workflow_id` (required), `vendor_data` (MEVORA uid),
`callback`, `metadata`, `language`, `sandbox_scenario` (sandbox apps only).
Response: `session_id`, `session_token` (12 chars), `url`, `status`.
Decision re-fetch: `GET /v3/session/{session_id}/decision/`.

**Flutter SDK** — `didit_sdk: ^4.9.0`. Flutter 3.3+ / Dart 3.11+, Android API
23+ with Java 17+, iOS 13.0+ (15.0+ only for NFC, which MEVORA does not use).
Android permissions are declared by the plugin; iOS needs
`NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription`
(`NSMicrophoneUsageDescription` only if video liveness is enabled — passive
liveness does not need it). Launch:
`DiditSdk.startVerification('<session_token>')`. Returns
`VerificationCompleted` / `VerificationCancelled` / `VerificationFailed`.
The docs state plainly that the SDK returns status only and that full decision
data arrives by webhook — **the SDK result is a UI hint, never approval.**

**Webhook** — signed HMAC-SHA256 with the destination's `secret_shared_key`,
which is **not** the API key: it is returned once by
`POST /v3/webhook/destinations/`. Headers: `X-Signature-V2` (canonical JSON:
sorted keys, compact separators, unescaped Unicode — preferred), `X-Signature`
(raw transmitted bytes), `X-Signature-Simple` (deprecated, envelope-only),
plus `X-Timestamp`. Reject when `abs(now - X-Timestamp) > 300`.

**Session statuses** — case-sensitive, spaced: `Not Started`, `In Progress`,
`Awaiting User`, `In Review`, `Resubmitted`, `Approved`, `Declined`, `Expired`,
`Abandoned`, `Kyc Expired`. Only `Approved` verifies.

**MVP workflow modules**

| Module | Purpose | Free / Paid | Required for MVP? |
|---|---|---|---|
| ID Verification | Government document authenticity + OCR | 500/month free, then metered | **Yes** |
| Passive Liveness | iBeta L1 PAD — user is physically present | 500/month free | **Yes** |
| Face Match 1:1 | Selfie ↔ document portrait | 500/month free | **Yes** |
| Device & IP Analysis | Fraud signal | 500/month free | Optional — include; it is free and MEVORA already fights fake profiles |
| AML / KYB / NFC / Proof of Address / Transaction Monitoring | — | Paid | **No** — explicitly out of scope |

**Webhook events**

| Event | Why needed | Handler action |
|---|---|---|
| `status.updated` | The only signal that moves a session to `Approved` / `Declined` / `Expired` | Verify signature → check timestamp window → `vendor_data` → uid → idempotency on `event_id` → map status → transaction-write verification doc + `users/{uid}.isVerified` |
| `data.updated` | A reviewer edited verification data after a decision | **Not subscribed in MVP.** Revisit only if manual review is enabled |

Everything else (`user.*`, `business.*`, `transaction.*`, `travel_rule.*`) is
out of scope.

**Session creation security** — authenticated callable, App Check enforced,
`vendor_data` set from `request.auth.uid` and never from the request body, API
key resolved from Secret Manager at runtime, existing cooldown and attempt
gates reused unchanged. The client cannot name another user because it never
names a user at all.

## 5. Provider-neutral foundation (STEPS 5-6, implemented on this branch)

Backend `functions/src/identity/`:

- `identityVerificationStatus.ts` — `IdentityVerificationStatus`
  (`not_started | in_progress | in_review | verified | declined | expired | error`),
  `IdentityVerificationProvider`, `grantsVerifiedBadge` (the one predicate that
  may show the badge), `isTerminalIdentityStatus`, `canStartIdentityVerification`,
  `parseIdentityVerificationStatus`, `identityVerificationDocPath` →
  `users/{uid}/verification/identity`, and the minimal
  `IdentityVerificationRecord` shape.
- `diditStatusMapping.ts` — exact-match Didit status table and
  `correlationUidFromWebhook` (`vendor_data` only).
- `sumsubStatusBridge.ts` — legacy status → neutral vocabulary.

Flutter `lib/features/verification/domain/entities/`:

- `identity_verification.dart` — the same vocabulary as a Dart enum with
  `grantsVerifiedBadge` / `isTerminal` / `isInFlight` / `canStart`, wire codecs,
  and the minimal `IdentityVerification` model.
- `legacy_verification_bridge.dart` — `ProfileVerificationStatus` → neutral.

Unknown or malformed provider values map to `error`, never to a status that
could read as progress, and never to `verified`.

All of this is **additive and unreferenced by runtime code**. No existing call
site changed, so production behaviour is byte-identical.

## 6. Legacy Sumsub strategy (STEP 14)

Production (`mevora-d6ed0`) inspected read-only, counts only, no personal data
read, with a control query to prove the query shape works:

- control: `users` collection group → 5 documents (query shape valid)
- `verification` collection group, all descendants → **0 documents**
- `users` where `isVerified == true` → **0**
- `profiles` where `isVerified == true` → **0**
- total `users` documents → 129

**No real Sumsub-verified users exist.** Migration may remove provider-specific
state aggressively: no compatibility shim, no dual-read, no backfill, and no
user loses a badge. The legacy bridge above is retained as a cheap safety net
so the cutover stays reversible, not because data needs it.

Sumsub secrets stay in Secret Manager until Didit is validated in production.

## 7. Account deletion integration (STEP 13)

```
deleteUserAccount (callable, App Check, auth-only)
  → read users/{uid}/verification/identity → providerSessionId
  → delete verification doc + users/{uid} + profiles/{uid} + …
  → requestIdentityProviderErasure({uid, providerSessionId})
        DELETE https://verification.didit.me/v3/session/{session_id}/delete/
        body: {"deletion_instruction": "privacy_erasure", "instruction_id": "<uid>"}
  → auth.deleteUser(uid)
  → enqueue accountDeletionVerify job → automation drain verifies
```

Didit deletion characteristics, from the current docs:

- **Synchronous** — returns 200 with `face_retention_outcome`; the session
  disappears from the list and decision endpoints immediately.
- **Not idempotent at HTTP level** — first call 200, repeat 404. A 404 must be
  treated as success by the caller.
- **Retryable on 503** — the session is untouched, the same request is safe.
- **Rate limited** — 300 writes/min per API key, shared across POST/PATCH/DELETE.
- `deletion_instruction: "privacy_erasure"` is the GDPR Article 17 path and also
  purges retained biometric templates for the user.

Today `requestSumsubApplicantDeletion` in `main` is a **17-line stub that
deletes nothing provider-side**. PR #10 (`fix/sumsub-account-deletion`, OPEN)
replaces it with a real implementation. Phase 2 must not land a second,
conflicting rewrite of the same function — see the merge risk note below.

## 8. Verified badge migration (STEP 12)

Consumers today: `VerifiedProfileBadge` (settings, discovery card, discovery
details), `MevoraAvatar`, `verificationEntryTitle/Subtitle/Icon`,
`match_connection_tile`, `profile_tab_page`. Every one of them reads
`users/{uid}.isVerified` or a server-written mirror of it.

The migration keeps that single authority and only changes who writes it: the
Didit webhook, after signature and timestamp validation, when and only when
`grantsVerifiedBadge(mapDiditStatus(payload.status))` is true. No screen gains
a new source; the `profiles[isVerified] || users[isVerified]` double-read in
discovery is collapsed to the single field.

## 9. External setup required before Phase 2

1. Didit account plus a **sandbox** Application (`mode == SANDBOX`) — its own API key.
2. A workflow with ID Verification + Passive Liveness + Face Match 1:1
   (+ Device & IP Analysis) — record its `workflow_id`.
3. A webhook destination via `POST /v3/webhook/destinations/` — capture
   `secret_shared_key`, which is shown only once.
4. Secret Manager (`mevora-d6ed0`), server-side only:
   `DIDIT_API_KEY`, `DIDIT_WEBHOOK_SECRET`, `DIDIT_WORKFLOW_ID`.
5. None of the above may enter Flutter source, dart-defines, Remote Config,
   client-readable Firestore, the app bundle or Git.

## 10. Merge risk

`functions/src/deleteAccount.ts` and
`functions/src/sumsub/sumsubApplicantLifecycle.ts` are both rewritten by the
open PR #10. This branch touches neither. Phase 2 will touch both, so PR #10
should land (or be closed) before Phase 2 starts.

Shared files touched by this branch: `functions/package.json` only — one test
filename appended to the `test` script, required by
`functions/test/testSuiteCoverage.test.cjs`.

## 11. Phase 2 task

**Didit Sandbox Session + Flutter Verification Flow.** Implement
`createIdentityVerificationSession` (callable, App Check, `vendor_data` from
`request.auth.uid`, reusing the existing cooldown and attempt gates), the
signed `diditWebhook` (`X-Signature-V2`, 300s timestamp window, `event_id`
idempotency, writes `users/{uid}/verification/identity` and
`users/{uid}.isVerified`), swap `flutter_idensic_mobile_sdk_plugin` for
`didit_sdk`, and run a real sandbox session end to end before claiming
anything works.

---

## Flow

```
CURRENT (Sumsub)
  Flutter → createSumsubAccessToken (App Check, auth uid)
         → SNSMobileSDK.launch(token)
  Sumsub → sumsubWebhook (x-payload-digest, HMAC-SHA256)
         → users/{uid}/verification/sumsub + users/{uid}.isVerified
         → badge

PROVIDER-NEUTRAL FOUNDATION (this branch, not yet wired)
  IdentityVerificationStatus / Provider / Record
  grantsVerifiedBadge — the one badge predicate
  mapDiditStatus · mapLegacySumsubStatus — translation at the boundary
  users/{uid}/verification/identity — provider-neutral path

DIDIT TARGET
  Flutter → createIdentityVerificationSession (App Check, vendor_data = auth uid)
         → POST /v3/session/ (x-api-key, server-side)
         → DiditSdk.startVerification(session_token)   [result = UI hint only]
  Didit  → diditWebhook (X-Signature-V2 + X-Timestamp ≤ 300s, event_id idempotent)
         → mapDiditStatus → users/{uid}/verification/identity
         → users/{uid}.isVerified                      [authoritative]
         → badge
  Delete → DELETE /v3/session/{id}/delete/ privacy_erasure → accountDeletionVerify
```
