# Face Anchor — verified profile photo

A member may fill their profile with photos of anything safe: a trip, a pet, a
hobby. What MEVORA guarantees is narrower and stronger: **the primary photo of
a profile under the rule is one the server matched to the live account owner.**
That photo is the member's _Face Anchor_.

"The photo contains a face" is not enough — it could be anyone's. A Face
Anchor is verified by a fresh selfie that passes a liveness check and then a
1:1 face match against that specific profile photo.

This is separate from identity verification (`docs/DIDIT_INTEGRATION.md`).
Identity verification answers "did this member complete the identity
workflow?" and drives the account's Verified seal. Face Anchor answers "is
this profile photo the person holding the account?" and has its own mark.

## The rules

| Rule | Where it is imposed |
|---|---|
| 3–6 photos; secondary photos need not show the member | unchanged |
| A profile under the rule has at least one Face Anchor | `completeOnboarding`, `isProfileDiscoverable` |
| The primary photo is a Face Anchor, first in the array, `order: 0` | `moderation/photoInvariants.ts` |
| The last Face Anchor cannot be removed | `moderation/photoInvariants.ts` (it is restored); `moderation/deleteProfilePhoto.ts` (the delete is refused); `moderation/photoOrphanSweep.ts` (it is never swept) |
| A removed anchor does not stay verified | `moderation/photoInvariants.ts` |
| A rejected photo loses its verdict; a photo held in review is not usable while held | `photoModerationLedger.ts` |
| An already moderated photo id cannot be re-uploaded with other bytes | `processPendingProfilePhoto` |

The app applies the same rules (`lib/features/settings/domain/validators/photo_policy.dart`)
so the member is told before a write is refused. That is a courtesy, not the
authority: a client that skipped them would have its write corrected.

## Authority

`profiles/{uid}.photos` is an array the client rewrites whole, and Firestore
rules cannot validate array elements. So, exactly as with moderation:

- **The verdict** lives on the photo's moderation ledger entry,
  `users/{uid}/photoModeration/{imageId}.faceAnchor` =
  `{status: "verified", verifiedAt, provider, attemptId, storagePath}`.
  Admin SDK only. `storagePath` pins the verdict to the published object it
  was made about.
- **The projection** `photos[].faceAnchorVerified: true` is rewritten from the
  ledger by `enforceProfilePhotoModeration` on every profile write. A forged
  value does not survive the next pass, and nothing that decides eligibility
  reads it.
- **`profiles/{uid}.faceAnchorRequired`** and **`.faceAnchorPhotoIds`** are
  top-level fields absent from the profile rules' allowlists. Only the server
  writes them; eligibility reads these.
- **The attempt** `users/{uid}/faceAnchor/state` is owner-readable and never
  client-writable. It holds progress and the attempt budget, nothing else.

## Verification flow

```
app                               backend                         provider
 │ startFaceAnchorVerification ──▶ photo is the caller's, approved,
 │   {photoId, consentVersion}     not yet verified; opens an attempt
 │ ◀── {attemptId, uploadPath}
 │ capture selfie (camera only)
 │ upload ───────────────────────▶ face-anchor/pending/{uid}/{attemptId}
 │ submitFaceAnchorVerification ─▶ claim attempt (budget spent here)
 │   {attemptId}                   liveness(selfie) ──────────────▶
 │                                 match(selfie, photo) ──────────▶  only if live
 │                                 compare-and-set finalise
 │ ◀── {status, reason}            delete selfie (always)
```

- The request fields above are the only ones read. There is no field that
  selects a provider, a test mode or an outcome.
- `submit` is idempotent: a repeat returns the recorded result, a concurrent
  call reports `processing`, and neither re-runs (or re-bills) anything.
- Finalisation is one transaction that lands only if the attempt is still the
  member's current one and still `processing`, the account exists, the photo
  is still on the profile and the ledger still calls the same published object
  approved. It uses `update` only, so a result arriving after account deletion
  re-creates nothing.
- After a restart the app reads `faceAnchor/state`; it never infers a result
  from what it did locally.

### Budget

Per member: 5 billed attempts per 24 h and a 20 s cooldown, spent when a
submission starts processing. Opening an attempt is free (and rate limited on
its own). A provider outage gives the attempt back, at most twice per window.
Across all members: `FACE_ANCHOR_DAILY_GLOBAL_CAP` billed verifications per UTC
day; beyond it verification is unavailable and an error is logged.

## Biometric data

| | |
|---|---|
| Selfie | Stored only at `face-anchor/pending/{uid}/{attemptId}`, write-once, unreadable by any client including its owner. Deleted on every exit of `submit`, when a newer attempt replaces it, on account deletion, and by `faceAnchorSelfieSweep` (every 15 min, anything older than 15 min, whatever its state). |
| Stored | `photoId`, `attemptId`, provider name, status, a coarse reason code, consent version and time, timestamps, attempt counters, the published `storagePath`. |
| Never stored | The selfie, similarity or liveness scores, face embeddings or landmarks, the provider's response or request id, estimated age or gender. |
| Sent to the provider | The selfie and the profile photo, re-encoded as JPEG with metadata stripped (no EXIF, no GPS), with `save_api_request=false` — Didit then keeps neither the images nor a session and does not enrol the face. No member identifier is sent. |
| Logged | A reason code. Never a URL, bytes, a score or a provider message. |

The member agrees to the check on the verification screen before the camera
opens; `start` refuses without the current `consentVersion`, and the version
and time are recorded on the attempt.

The reason codes are the whole vocabulary a member or an admin ever sees:
`liveness_failed`, `face_mismatch`, `photo_face_unclear`, `selfie_invalid`,
`technical_error`.

## Provider

`functions/src/faceAnchor/provider.ts` is the seam: two questions, answered in
closed words (`live | not_live | no_face`, `match | no_match |
reference_unusable`).

- **Didit** (`diditFaceProvider.ts`, `identity/didit/diditFaceClient.ts`):
  standalone `POST /v3/passive-liveness/` and `POST /v3/face-match/`,
  multipart, `x-api-key`. Only the exact word `Approved` passes; an unknown
  word is an error, never a pass. A profile photo with no face, or more than
  one, cannot be an anchor.
- **Emulator fake** (`fakeProvider.ts`): deterministic outcomes for QA.

Selection (`resolveProvider.ts`) reads the server's environment only:

| Environment | Provider |
|---|---|
| Functions emulator | the fake, always — Didit is never contacted |
| Deployed, `DIDIT_API_KEY` set **and** `DIDIT_ENVIRONMENT=live` | Didit |
| Anything else | none: verification is unavailable (fails closed) |

A sandbox Didit key answers these two APIs with a canned `Approved`. That is
why an undeclared environment gets no provider rather than one that verifies
everybody.

### Configuration

| Name | Kind | Default | Meaning |
|---|---|---|---|
| `DIDIT_API_KEY` | secret | — | Shared with identity verification |
| `DIDIT_ENVIRONMENT` | param | `sandbox` | Must be `live` for Face Anchor to run |
| `FACE_ANCHOR_ENFORCEMENT` | param | unset: off when deployed, on in the emulator | `on` / `off`. New members must have a Face Anchor to finish onboarding |
| `FACE_ANCHOR_MATCH_THRESHOLD` | param | `50` | Didit declines a match at or below this |
| `FACE_ANCHOR_LIVENESS_THRESHOLD` | param | `30` | Didit declines liveness at or below this |
| `FACE_ANCHOR_DAILY_GLOBAL_CAP` | param | `2000` | Billed verifications per UTC day |

No secret reaches the app. The app never calls Didit.

## Who is under the rule

- A profile completed while enforcement is **on** gets
  `faceAnchorRequired: true` and cannot complete without an anchor.
- A member who completed **before** the rule (or while enforcement was off) is
  left exactly as they were: they sign in, they stay discoverable, and their
  photos are **not** treated as verified. They see an invitation to verify a
  photo on the profile tab and the edit page.
- The first verified photo puts a member under the rule from then on.

There is no bulk migration and none was run. Requiring an anchor from every
existing member is a separate decision, to be taken with real numbers.

A member under the rule whose only anchor is rejected by moderation stops being
shown to others (Discover, Picks, Likes You) until they verify another photo.
They can still use the app.

## Enforcement switch and rollout order

`FACE_ANCHOR_ENFORCEMENT` exists because the backend and the app do not ship
at the same moment. Turned on before the new app is in members' hands — or
before a live provider is configured — it would stop every sign-up.

1. Deploy functions, Firestore rules and Storage rules together.
2. Release the app.
3. Configure the live Didit key and `DIDIT_ENVIRONMENT=live`. Verify one photo
   with the right face (expect verified) and one with a wrong face (expect not
   verified) before going further — the Didit response shapes here were
   implemented from the documentation, not from a live response.
4. Set `FACE_ANCHOR_ENFORCEMENT=on`.

## Emulator QA

The emulator always uses the fake provider and enforces the rule. The outcome
is trusted local server state — `devControl/faceAnchor`, denied to every client
by the rules:

```powershell
$env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
$env:FIREBASE_STORAGE_EMULATOR_HOST = "127.0.0.1:9199"
node tool/faceAnchorDev.cjs status [uid]
node tool/faceAnchorDev.cjs outcome success | liveness-fail | mismatch | provider-error [--once]
node tool/faceAnchorDev.cjs clear
node tool/faceAnchorDev.cjs budget-reset <uid>
node tool/faceAnchorDev.cjs sweep [--all]     # the schedule does not fire in the emulator
```

The tool refuses to run unless the emulator hosts are loopback addresses.

## Tests

| Suite | Covers |
|---|---|
| `functions/test/faceAnchorService.test.cjs` | state machine, idempotency, budget, selfie deletion, sweep, cross-member attempts |
| `functions/test/faceAnchorInvariants.test.cjs` | projection forgery, dedupe, last anchor, primary, moderation, re-upload refusal |
| `functions/test/faceAnchorProvider.test.cjs` | Didit request/response, fail-closed mapping, provider selection |
| `functions/test/faceAnchorGate.test.cjs` | discoverability gate, budget arithmetic |
| `functions/test/faceAnchorOnboarding.test.cjs` | `completeOnboarding`, legacy members, Likes You |
| `functions/test/faceAnchorDeletion.test.cjs` | account deletion and its verification |
| `firebase/tests/*.security.emulator.test.mjs` | Firestore and Storage rules |
| `test/features/face_anchor/` | photo policy, controller, verification screen, onboarding |

## Known limits

- Passive, single-frame liveness is standard-grade. A modified client can
  upload an image instead of using the camera; the liveness check, and the
  refusal of a selfie identical to the profile photo, are the defences. Didit's
  hosted active-liveness flow would be stronger.
- `image_picker` asks for the front camera; Android may open the rear one.
- A forged `faceAnchorVerified` in `photos[]` is visible on the profile
  document until the trigger runs (seconds). Nothing that grants anything
  reads it.
- A whole-array write from a stale snapshot that omits an anchor, while another
  anchor remains, drops that anchor's verdict; the member verifies it again.
- `getSameTasteProfiles` does not apply the discoverability gate (pre-existing).
