# Didit identity verification — operations

How the feature is put together, what has to exist outside this repository
before it can run, and how to bring it up.

Companion documents: `docs/DIDIT_MIGRATION_PHASE1.md` (the Sumsub audit and
why the migration is shaped this way) and
`docs/IDENTITY_VERIFICATION_PRIVACY.md` (what is stored, who can read it, and
what deletion does).

---

## Architecture

```
Flutter
  └─ createIdentityVerificationSession  (callable, App Check, auth-only)
       └─ POST /v3/session/             x-api-key, server-side
            vendor_data = request.auth.uid
            callback    = mevora://verify/identity
  ← { providerSessionId, url }
  └─ url_launcher → Didit hosted flow
       ID Verification → Passive Liveness → Face Match 1:1
  └─ mevora://verify/identity           (app_links; a hint, not a verdict)
       └─ getIdentityVerificationState  → re-read backend state

Didit
  └─ status.updated → identityVerificationWebhook
       verify X-Signature-V2 · X-Timestamp within 300s
       vendor_data → uid · event_id idempotency · ordering guard
       if it would verify: GET /v3/session/{id}/decision/  ← the trusted read
       └─ users/{uid}/verification/identity
          users/{uid}.isVerified + profiles/{uid}.isVerified  (one transaction)
```

The backend is authoritative at every step. The SDK-less hosted flow means
nothing on the device ever holds a credential, and the return deep link
carries no verdict — it only triggers a re-read.

## Verification state machine

```
not_started ──start──▶ pending ──user opens──▶ in_progress
                           │                        │
                           │                        ├──▶ in_review ──▶ verified
                           │                        ├──▶ verified
                           │                        └──▶ declined
                           └──timeout/walk away──▶ expired

verified   — terminal; badge on. Only Didit "Approved", re-confirmed
             server-side, produces it.
declined   — terminal; badge off. Retryable after cooldown.
expired    — terminal; badge off. Covers Didit "Expired", "Abandoned" and
             "Kyc Expired". Retryable.
error      — any provider value MEVORA has not reviewed. Never grants the
             badge, never reads as progress.
```

Didit status → MEVORA status (`diditStatusMapping.ts`). Didit's strings are
case-sensitive and contain spaces; matching is exact, and anything unmatched
becomes `error` rather than a guess.

| Didit | MEVORA |
|---|---|
| `Not Started` | `not_started` |
| `Awaiting User` | `pending` |
| `In Progress`, `Resubmitted` | `in_progress` |
| `In Review` | `in_review` |
| `Approved` | `verified` |
| `Declined` | `declined` |
| `Expired`, `Abandoned`, `Kyc Expired` | `expired` |
| anything else | `error` |

## Didit console prerequisites

Nothing below is in this repository, and the feature cannot run until it
exists.

1. **A sandbox Application** (`mode == SANDBOX`). It has its own API key.
   Every provider call is mocked, no session is billed, and webhooks carry
   `"environment": "sandbox"`. Use it for all development and testing; a live
   application is a separate promotion step.
2. **A workflow** containing ID Verification, Passive Liveness and Face Match
   1:1, optionally Device & IP Analysis. All four are inside Didit's 500/month
   free allowance. Do not add AML, KYB, NFC, Proof of Address or Transaction
   Monitoring — MEVORA has no requirement for them and each is billed. Record
   the `workflow_id`.
3. **A webhook destination** via `POST /v3/webhook/destinations/`, pointed at
   the deployed `identityVerificationWebhook` URL, subscribed to
   `status.updated` only. The response carries `secret_shared_key` **once** —
   capture it then.
4. **Retention policy** for the application (Console → App Settings → Data).
   Not managed from this repository.

## Secrets

| Name | What | Where |
|---|---|---|
| `DIDIT_API_KEY` | Authenticates MEVORA to Didit | Cloud Functions secret |
| `DIDIT_WEBHOOK_SECRET` | The destination's `secret_shared_key` | Cloud Functions secret |
| `DIDIT_WORKFLOW_ID` | Console workflow id | Functions param / env |
| `DIDIT_ENVIRONMENT` | `sandbox` (default) or `live` | Functions param / env |
| `DIDIT_BASE_URL` | Defaults to `https://verification.didit.me` | Functions param / env |
| `DIDIT_CALLBACK_URL` | Defaults to `mevora://verify/identity` | Functions param / env |

```bash
firebase functions:secrets:set DIDIT_API_KEY --project mevora-d6ed0
```

`DIDIT_API_KEY` and `DIDIT_WEBHOOK_SECRET` are **different values**. Verifying
a webhook with the API key would accept every forgery; the code reads them
from separate names and a test asserts they are not interchangeable.

None of these may become a dart-define, a Remote Config value, a
client-readable Firestore field, or part of the app bundle. `.gitignore`
blocks both secret names; `functions/.env.example` documents them without
values.

## Behaviour when Didit is not configured

The default state of this repository today, and it is a supported state:

- `resolveDiditConfig()` returns `null` on any missing or partial value.
- `createIdentityVerificationSession` throws `failed-precondition` /
  `verification-not-configured`.
- The app shows "Verification is temporarily unavailable" and does not crash.
- The webhook answers `503` and writes nothing.
- `DIDIT_ENVIRONMENT` defaults to `sandbox`, so a half-configured deployment
  is never treated as live.

Nothing degrades to "assume verified". The failure direction is always away
from the badge.

## Local development

`functions/.env` is read before Secret Manager, so the emulator can run with
sandbox values. App Check enforcement is off under
`FUNCTIONS_EMULATOR=true`; it is on everywhere else.

The webhook needs a public URL, so for local work either use the Didit
console's redelivery against a deployed sandbox function, or post a body
signed with the sandbox `secret_shared_key` directly — the signature and
freshness checks are the same code either way.

## Sandbox verification procedure

Not yet performed — no Didit account exists at the time of writing. When one
does:

1. Deploy to a sandbox-configured project.
2. Register the webhook destination against the deployed function URL.
3. Sign in, open Profile → Verify, and complete the hosted flow with Didit's
   sandbox document fixtures. **Never a real identity document.**
4. Confirm `users/{uid}/verification/identity` moves
   `pending → in_progress → verified`, and the badge appears only afterwards.
5. Exercise, using `sandbox_scenario`: decline, expiry, in-review, cancel
   mid-flow, kill the app mid-flow and reopen, and a duplicate webhook
   delivery.
6. Two accounts: confirm A cannot read or affect B's verification state.
7. A disposable account: delete it, confirm the verification document is gone
   and either the Didit session is erased or
   `identityErasurePending/{uid}` exists with a job behind it.

## Rollout

1. Land the branches in order (see below), with PR #10 first.
2. Provision sandbox secrets; deploy; run the procedure above.
3. Create the live Didit application and workflow, set `DIDIT_ENVIRONMENT=live`
   with the live key and a live webhook destination.
4. Only once live verification is observed working: remove
   `functions/src/sumsub/` and its Secret Manager entries.

## Remaining Sumsub references, and why each is still there

| Reference | Why |
|---|---|
| `functions/src/sumsub/*` | `deleteAccount` still calls `requestSumsubApplicantDeletion` for accounts created before the migration. The verification callable and webhook are **no longer exported**, so they are not deployed; the module stays as the rollback path until Didit is validated in production. |
| `functions/src/identity/sumsubStatusBridge.ts`, `lib/.../legacy_verification_bridge.dart` | Read a pre-migration verification document so it renders rather than crashing. Production holds none; this is insurance. |
| `users/{uid}/verification/sumsub` in `deleteAccount` and `deletionVerify` | The legacy document is still deleted and still proven gone. |
| `firestore.rules` comments | Explanatory text naming the historical provider. |
| `discovery_candidate.dart` | A comment only. |

Nothing outside that table names a provider, and no domain contract does.

## Branch order

```
feature/didit-identity-verification      audit + provider-neutral foundation
  └─ feat/didit-verification-foundation  provider-neutral domain
       └─ feat/didit-backend-session-webhook   session + signed webhook
            └─ feat/didit-flutter-verification-flow   app flow
                 └─ feat/didit-deletion-privacy       deletion + privacy
                      └─ feat/didit-hardening         this document
```

PR #10 (`fix/sumsub-account-deletion`) touches `deleteAccount.ts` and
`sumsubApplicantLifecycle.ts` and should land before
`feat/didit-deletion-privacy`.
