# Photo Moderation Pipeline

Mevora uses a server-controlled photo lifecycle without AI/ML in the first implementation.

## Lifecycle

```text
pending → processing → approved
                     → manual_review
                     → rejected
```

## Client rules

- Clients upload to `users/{uid}/profile/pending/{imageId}`
- Clients write `moderationStatus: pending` only
- Approved photos are published under `users/{uid}/profile/photos/` by Cloud Functions
- A photo id is moderated once: uploading to `pending/{imageId}` again after a
  decision is ignored and the new bytes are deleted, so an approved photo cannot
  be swapped for another image

## Backend modules

| File | Role |
|------|------|
| `functions/src/moderation/manualModerationProvider.ts` | Technical validation (type, size, magic bytes, dimensions) |
| `functions/src/moderation/photoModerationService.ts` | Orchestration, publish, retry, report hook |
| `functions/src/moderation/profileModerationGuard.ts` | Reconciles `profiles/{uid}.photos` against the server-owned ledger on every profile write |
| `functions/src/moderation/photoModerationLedger.ts` | The ledger (`users/{uid}/photoModeration/{imageId}`): the authority for moderation status |
| `functions/src/moderation/photoInvariants.ts` | What the photos array must look like: one id once, the primary photo, the Face Anchor rules |
| `functions/src/backend.ts` | `onProfilePhotoUploaded` trigger |

## Face Anchor

Whether a photo is the member themselves is a separate, later question, decided
by the face verification pipeline and recorded on the same ledger entry. A Face
Anchor must pass both: moderation approval **and** face verification. Rejecting
a photo removes its verdict. See `docs/FACE_ANCHOR.md`.

## Report hook

`reportUser` marks the reported profile for `manual_review`.

## Future AI provider

Add `AIModerationProvider` beside `manualModerationProvider.ts` and route through `photoModerationService.ts`.

## Deploy requirements

- Deploy Functions + Firestore rules + Storage rules
- Storage trigger region: `us-east1`
- Scheduled retry runs inside `retentionCleanup`
