# Identity verification — data, privacy and deletion

What MEVORA stores when a user verifies their identity, what it never stores,
who can read it, and what happens to all of it when the account is deleted.

Provider: **Didit** (ID Verification + Passive Liveness + Face Match 1:1,
plus Device & IP Analysis). Architecture: `docs/DIDIT_MIGRATION_PHASE1.md`.

---

## What MEVORA stores

One document per user: **`users/{uid}/verification/identity`**. That is the
whole footprint. There is no second place verification state lives, which is
what makes deletion provably complete.

| Field | What it is | Deletion |
|---|---|---|
| `schemaVersion` | Document shape version | Delete with account |
| `provider` | `didit` | Delete with account |
| `providerSessionId` | Didit session reference — the handle used to ask Didit to erase its copy | Delete with account, **after** erasure is requested |
| `status` | `not_started \| pending \| in_progress \| in_review \| verified \| declined \| expired \| error` | Delete with account |
| `reason` | MEVORA's own category code (`document_unreadable`, `liveness_failed`, `face_mismatch`, `manual_review`, `provider_error`) — never Didit's wording | Delete with account |
| `createdAt` / `updatedAt` / `verifiedAt` | Server timestamps | Delete with account |
| `attemptCount` / `lastAttemptAt` | Abuse gate bookkeeping | Delete with account |
| `lastEventId` / `lastEventAtMs` | Webhook idempotency and ordering keys | Delete with account |

Plus one derived flag: **`users/{uid}.isVerified`** — the badge. Server-written
only, deleted with the account document.

`identityErasurePending/{uid}` exists only while a provider-erasure request is
outstanding: `uid`, `provider`, `providerSessionId`, `attempts`, `lastOutcome`,
two timestamps. No name, no email, no identity data. It is created *by* a
deletion and removed the moment Didit confirms erasure, so it cannot become a
shadow record of a departed user. If it is still there, it means the user's
data is still with the provider — which is a fact MEVORA needs to keep until
it is not.

## What MEVORA never stores

Not in Firestore, not in Storage, not in logs, not in the export:

- document images, passport or ID scans
- selfies, portrait images, liveness video
- biometric templates or face embeddings
- document numbers, MRZ contents, extracted identity fields
- raw Didit decision bodies or webhook payloads
- Didit's own reject labels and reviewer comments
- temporary media URLs Didit returns

These live with Didit. The transport layer (`diditClient.ts`) reduces every
response to four statuses before it returns, so there is no code path that
could persist them by accident.

## Who can read what

| Data | Owner | Other users | Anonymous |
|---|---|---|---|
| `users/{uid}/verification/identity` | read | **no** | **no** |
| `users/{uid}.isVerified` | read | **no** (private account doc) | **no** |
| `profiles/{uid}.isVerified` — the public badge | read | read | read |
| `identityErasurePending/{uid}` | **no** | **no** | **no** |

No client may write any of these. `users/{uid}/verification/{docId}` is
`allow read: if isOwner(userId); allow create, update, delete: if false;` — a
wildcard, so a future document id is covered without a rules change.
`identityErasurePending` is covered by the default deny and is deliberately
never granted an exception.

The public projection carries the badge and nothing else: no session id, no
reason code, no timestamps, no provider name.

## Account deletion

```
deleteUserAccount
  ├─ read users/{uid}/verification/identity → providerSessionId
  ├─ delete verification/identity + verification/sumsub + users/{uid}
  │    + profiles/{uid} + every other user document
  ├─ requestIdentityProviderErasure({uid, providerSessionId})
  │    DELETE /v3/session/{id}/delete/  {"deletion_instruction":"privacy_erasure"}
  │    ├─ 200            → erased, nothing pending
  │    ├─ 404            → already absent; that is the state we asked for
  │    └─ anything else  → identityErasurePending/{uid}, job enqueued
  ├─ auth.deleteUser(uid)
  └─ enqueue accountDeletionVerify  → drain confirms no remnants,
                                      including both verification documents
```

Deletion never blocks on the provider. A Didit outage does not abort a
deletion the user has already been promised: the account goes, and the
outstanding request survives as a pending record.

`deleteUserAccount` returns `identityProviderErased: true|false`. It says
which happened rather than reporting total success either way.

### When provider erasure fails

The `identity_provider_erasure` automation job retries it. When the job still
cannot confirm, it reports `complete: false`, which the runner routes to
**manual review** — not to `failed`. Identity documents a provider still holds
for a deleted user is a compliance matter that a person should see, not a
transient error that should quietly exhaust a retry budget.

Retry is safe: a repeat call returning 404 means the session is already gone,
which the code treats as confirmation and clears the pending record.

### Late webhooks

A Didit event arriving after deletion cannot resurrect anything.
`applyIdentityProviderEvent` reads `users/{uid}` inside the transaction and
refuses when it does not exist — so no user document, no profile and no
verification record is recreated, whatever the event says and however many
times it is redelivered. The webhook answers 200 so Didit stops retrying.

Three other refusals apply to live accounts too: a session id this user never
started, an event id already applied, and an event older than the one already
applied.

## Data export

`exportUserData` includes `status`, `provider`, `reason`, `verifiedAt` and
`updatedAt` — everything MEVORA holds that is about the user.

Excluded: `providerSessionId` (backend-only correlation, not user data) and
the webhook bookkeeping fields. Nothing else exists to exclude, because
nothing else was ever stored.

> Note: before this change the export read `status` and `reviewedAt` from the
> verification document. Neither field has ever existed on it, so that section
> always exported nulls. It now reads the fields the document actually has.

## What the user is told

The verification screen says their ID is checked by a verification partner and
links to the privacy policy. It never shows a session id, a provider error, a
webhook state or Didit's wording about their document — a decline is explained
by which step to redo, and any unmapped code falls through to generic copy.

## Still outstanding

- Didit is not yet configured (`DIDIT_API_KEY`, `DIDIT_WEBHOOK_SECRET`,
  `DIDIT_WORKFLOW_ID` are unset), so provider-side erasure has not been
  exercised against a real session. The code path is tested against a mocked
  provider, including the 404, 503 and unconfigured cases.
- Didit's own retention policy for the application (`face_retention_policy`)
  is a console setting and is not managed from this repository.
