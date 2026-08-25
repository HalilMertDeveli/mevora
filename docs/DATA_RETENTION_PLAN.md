# Mevora — Data Retention & Orphan Cleanup Plan

## Current (implemented)

- Daily `retentionCleanup`: old notifications, ended calls (>30d), stale photo moderation retries.
- Account deletion (`deleteUserAccount`): Auth user, profile/prefs/privacy/location, likes, blocks, reports, tickets, purchases, devices/FCM, boosts, scores, relationship/question answers, crypto identity docs, presence, subscription, passedUsers, match messages/meta (match docs anonymized inactive), Storage `users/{uid}/` + `profiles/{uid}/`.

## Planned (not fully automated yet)

| Item | Policy proposal | Owner |
|------|-----------------|-------|
| Inactive match media in Storage | Delete encrypted blobs for matches inactive > 180 days | Scheduler CF |
| Soft-deleted messages | Already tombstoned client-side; hard-delete ciphertext after 90 days optional | Product |
| Cloud Function logs | Firebase default retention; avoid PII via `safeLogMeta` | Ops |
| Crashlytics | Non-dev only; scrub incidental PII in reporters | Client |
| Backups | Firebase PITR / GCS — legal hold delay before purge requires counsel | Legal + Ops |
| Orphan Storage | Weekly scan of `users/*/chat/` without active match | Scheduler |

## Soft vs hard delete

- **Account:** hard delete Auth + primary docs; matches kept inactive with “Deleted account” for peer UX.
- **Messages on unmatch:** deleted under match for deleting user path; peer history product decision.

This document is technical planning only — not a legal retention schedule.
