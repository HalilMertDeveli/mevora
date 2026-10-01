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
| `functions/src/moderation/deleteProfilePhoto.ts` | A member deletes one of their photos: array entry, stored objects, ledger entry |
| `functions/src/backend.ts` | `onProfilePhotoUploaded` trigger |

## Deleting a photo

The app calls `deleteProfilePhoto({photoId})`. Clients cannot delete anything
under `photos/` or `thumbs/` (Storage rules), so dropping a photo from
`profiles/{uid}.photos` only stops the profile mentioning it — the published
original, both variants and the ledger entry stay behind.

The callable is the only thing that deletes. Nothing reacts to an id leaving the
array, on purpose: reconciliation puts a removed last Face Anchor back, and a
stale whole-array client write can drop a photo the next write restores. An id
missing from the array is not a decision to delete.

1. One transaction refuses the request, or removes the photo from the array,
   re-imposes the photo invariants on the rest and deletes the ledger entry.
2. The published original, the `_thumb` and `_card` variants and the pending
   upload are deleted. If one could not be, the answer is
   `cleanup: "incomplete"` and the failure is logged; calling again retries.

The ledger entry goes with the array entry because it is what tells the pipeline
the photo still exists. A moderation result that was on its way when the member
deleted the photo finds no entry and is dropped (`setPhotoModerationStatus`),
and an upload whose pending object is already gone is not processed at all —
either would otherwise write the photo back onto the profile.

| Refusal (`failed-precondition`) | When |
|---|---|
| `photo_min_required` | A completed profile would drop below 3 photos |
| `photo_last_face_anchor` | The photo is the member's only usable Face Anchor — judged on the ledger, so also while a stale write has it missing from the array |
| `photo_processing` | The moderation pipeline is on this photo right now (under 5 minutes); its result would write the photo back |

A photo that is `rejected` or in `manual_review` leaves the profile but keeps
its ledger entry and stored image (`cleanup: "retained"`): the entry is the
moderation record and what stops the id being uploaded again, and a reviewer
still needs the image.

The kept entry is stamped `removedByMemberAt`. From then on the photo is never
put back on the profile: a moderation result for it is recorded on the ledger
without being added to the array, and a redelivered upload event does not
moderate it again. When a reviewer later decides it (`adminReviewPhoto`):

| Decision | What happens to a photo the member removed |
|---|---|
| Approve | Nothing is published or restored. The stored objects and the ledger entry are deleted — the deletion the member asked for is finished. The approval is still recorded (action + audit, `placement: "removed_by_member"`). |
| Reject | Quarantined and recorded as for any other photo; the entry stays `rejected`. No rejected photo is added to the profile. |

A review decision never adds a photo to a profile, with or without the stamp:
it updates the photo if it is in the array and is otherwise only recorded
(`placement: "not_on_profile"`). Without the stamp nothing is deleted, because
an id missing from the array is not proof of a removal — it is also what a
photo looks like between its upload and the client's array write. Only the
upload pipeline adds a missing photo.

Older app versions still rewrite the array themselves. That keeps working and
keeps leaving the stored copy behind; calling `deleteProfilePhoto` for such an
id later removes the leftovers. An app talking to a backend that does not have
the callable yet falls back to the same rewrite.

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
