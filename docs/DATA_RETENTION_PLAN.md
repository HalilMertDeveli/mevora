# Mevora — Data Retention & Orphan Cleanup Plan

## Current (implemented)

- Daily `retentionCleanup`: old notifications, ended calls (>30d), stale photo moderation retries.
- Account deletion (`deleteUserAccount`): Auth user, profile/prefs/privacy/location, likes, blocks, tickets, purchases, devices/FCM, boosts, scores, relationship/question answers, crypto identity docs, presence, subscription, passedUsers, `authRateLimits/spotify_{uid}`, Storage `users/{uid}/` + `profiles/{uid}/`, and support attachments under `support/{ticketId}/` for tickets the user owns (ownership resolved from `supportTickets.userId`, never from the object path).
- Post-deletion verification (`accountDeletionVerify`): enqueued by `deleteUserAccount`, executed by `processAutomationTask` with `automationJobDrain` as the 15-minute fallback. Read-only — an incomplete deletion lands in `manual_review` and surfaces via `health.signals.hasJobsNeedingReview`.

### Deliberate retention on account deletion

| Data | Behaviour | Why |
|------|-----------|-----|
| Match documents | Retained, marked inactive, deleted participant shown as "Deleted account" | Peer UX; the peer is a party to the match |
| Peer-authored messages | **Retained untouched** | They are the peer's own personal data, not the departing user's |
| Departing user's messages | Tombstoned in place (`deleted: true`, content fields cleared) | Erasure of their content without destroying the peer's thread |
| `reports` (both directions) | **Retained**, flagged `reporterDeleted` / `reportedUserDeleted` | A reported user must not be able to erase the moderation trail by leaving; a report they filed is evidence about someone else. Exposed only to an admin or the report's own reporter under `firestore.rules`. |
| `humorReports` filed by the user | Retained, flagged `reporterDeleted` | Same reasoning — content moderation evidence |

**Open policy item:** no retention *duration* is defined for retained moderation evidence, and
nothing purges it. `cleanupOldAuditLogs` implements a 180-day window but is not scheduled.
Setting that period is a legal/policy decision, not a code one — `LEGAL REVIEW REQUIRED`.

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
