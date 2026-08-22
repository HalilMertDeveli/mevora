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

## Backend modules

| File | Role |
|------|------|
| `functions/src/moderation/manualModerationProvider.ts` | Technical validation (type, size, magic bytes, dimensions) |
| `functions/src/moderation/photoModerationService.ts` | Orchestration, publish, retry, report hook |
| `functions/src/moderation/profileModerationGuard.ts` | Blocks client-side moderation escalation |
| `functions/src/backend.ts` | `onProfilePhotoUploaded` trigger |

## Report hook

`reportUser` marks the reported profile for `manual_review`.

## Future AI provider

Add `AIModerationProvider` beside `manualModerationProvider.ts` and route through `photoModerationService.ts`.

## Deploy requirements

- Deploy Functions + Firestore rules
- Storage trigger region: `us-east1`
- Scheduled retry runs inside `retentionCleanup`
