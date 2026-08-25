# Mevora Automation, Admin Panel & Operational Control

Last updated: 2026-08-25

## Phase 1 — Existing backend (summary)

See also codebase inventory. Key facts:

- Collections: `users`, `profiles`, `likes`, `matches`, `notifications`, `reports`, `blocks`, `purchases`, …
- Storage: `users/{uid}/profile/{pending|photos|thumbs}`, `users/{uid}/chat/{matchId}/…`
- Cloud Functions: discovery, social (swipe/match/block/report), notifications, boost, Spotify, relationship, Sumsub, deleteAccount
- Premium: Auth claim `premium` **or** `users/{uid}/subscription/current`
- Added in this pass: admin claim gate, `auditLogs`, `automationJobs`, Cloud Tasks + scheduled drain, Hosting `/admin` panel

## Automation inventory

### Fully automatic

| Automation | Trigger | Action | Auth | Retry | Rate limit | Idempotency | Audit | Failure | Human? | Privacy |
|---|---|---|---|---|---|---|---|---|---|---|
| Mutual match create | `recordSwipe` / `recordDiscoveryDecision` txn | Create `matches/{min_max}` | Caller auth | Client retry | CF | likeId + matchId | CF logs | No duplicate match | No | Names/photos denormalized |
| Like notification | like without match | Generic FCM only | System | failedNotifications | — | `incomingLike_*` | — | Retry | No | No liker UID in FCM |
| Match notification | `matches` onCreate | In-app + FCM | System | failedNotifications | FCM | `newMatch_{matchId}_{uid}` | — | Retry queue | No | No message content in FCM |
| Message notification | messages onCreate | Push + side effects | System | failedNotifications | message rate limit | `msg_{matchId}_{messageId}_{uid}` | — | Retry queue | No | No plaintext in FCM |
| Block apply | `blockUser` callable | blocks + unmatch | Caller | Client | — | blockId | — | Immediate | No | Hides peer |
| Report enqueue | reports onCreate | `adminReviewQueue` | System | — | report daily RL | `report_review_{id}` | job | Queue open | **Review only** | No E2EE read |
| Notification retention | schedule / job | Delete >30d | System | job retry | batch 400 | day key | job result | Skip | No | Deletes notifs |
| Call retention | schedule / job | Delete old calls | System | job retry | batch 200 | day key | job result | Skip | No | Signaling only |
| Stale pending photo cleanup | schedule / job | Delete old pending Storage | System | job retry | batch | day key | job + optional admin | Skip active | No | Pending only |
| Orphan chat media (dry default) | schedule / admin | List/delete orphans | System/admin | job retry | batch | day key | audit if admin | Conservative skip | Dry-run default | Chat paths |
| Deleted-account Storage remnant (dry default) | schedule / admin | Cleanup Storage if no user doc | System/admin | job retry | batch | day key | audit | Never if user exists | Dry-run default | Storage only |
| Premium expiry sync | schedule / job | `isPremium=false`, clear claim | System | job retry | batch 200 | day key | logs | Skip valid | No | Entitlement only |
| Discover eligibility refresh | schedule / job | Undiscover banned/missing | System | job retry | batch | day key | logs | Skip healthy | No | Public profile flag |
| Notification FCM retry | schedule / job | Resend failed FCM | System | max 5 | 50/run | failedNotifications id | — | manual_review | No | Type + ids only |
| Account deletion verify | post-delete enqueue | Check remnants | System | job | — | `deletion_verify_{uid}` | job | manual_review if gaps | If incomplete | Checks only |
| User doc repair | job | Fill missing safe fields | System/admin | job | — | keyed by uid | — | Skip if healthy | No | No privilege escalation |
| Photo moderation | Storage finalize | Process pending | System | stale retry | — | imageId | CF logs | Manual review status | Photo MR | Images |
| Boost expiry | schedule 15m | Expire boosts | System | — | CG query | boost id | logs | Skip | No | Boost wallet |

### Human-approved (admin)

| Action | Notes |
|---|---|
| Report resolve / escalate ban review | `adminResolveReport` — ban not auto-applied |
| User suspend / restore | `adminSetUserSuspension` + reason + audit |
| Permanent ban request | Queued `manual_review` only — not executed by automation |
| Cleanup destructive run | `adminRunCleanup` with `dryRun:false` + reason |
| Job manual retry | `adminRetryJob` |
| Grant/revoke admin claim | `adminSetAdminClaim` (existing admin only) |
| Audit log retention delete | Requires admin approval flag |

### Never automated

| Action | Why |
|---|---|
| Permanent Auth account delete (admin-forced) | Irreversible; user self-delete via `deleteUserAccount` only |
| Auto permanent ban | Abuse false positives |
| Premium refund / revoke money | Payment compliance |
| Reading E2EE message plaintext | Cryptographic privacy; reports use user-supplied evidence only |
| Client-writable admin role | Privilege escalation |
| Mass Storage delete without dry-run/audit | Data loss risk |

## Admin panel

- URL (Hosting): `/admin`
- Auth: Firebase email/password + custom claim `admin: true`
- Bootstrap first admin: `functions/scripts/setAdminClaim.mjs`
- Callables: `adminGetDashboard`, `adminSearchUsers`, `adminListReports`, `adminResolveReport`, `adminListJobs`, `adminRetryJob`, `adminRunCleanup`, `adminVerifyDeletion`, `adminSetUserSuspension`, `adminListAuditLogs`, `adminListReviewQueue`, `adminSetAdminClaim`

## Cloud Tasks

- Function: `processAutomationTask` (`onTaskDispatched`)
- Enqueue helper: `automation/tasksEnqueue.ts`
- Fallback: `automationJobDrain` every 15 minutes processes `queued` / `retrying`

## Scheduled jobs

| Function | Schedule |
|---|---|
| `automationDailySchedule` | every 24 hours |
| `automationJobDrain` | every 15 minutes |
| `retentionCleanup` | every 24 hours (compat; uses shared cleanup helpers) |
| `expireBoost` | every 15 minutes (existing) |
| `aggregateWeeklyMusicStats` | weekly (existing) |

## Job status collection

`automationJobs/{idempotencyKey}`: `queued | running | succeeded | failed | retrying | manual_review | cancelled`

## Cost / rate limit impact

- Daily suite: ~8 job docs/day + bounded Storage list (≤2k objects/prefix) + capped Firestore deletes (≤400 notifs, ≤200 calls)
- Drain: ≤30 job claims / 15 min
- Cloud Tasks: max 5 concurrent, 2/sec for automation processor
- Avoids full collection scans for dashboard (capped queries)
- Orphan/remnant cleanups default **dry-run** on schedule to avoid surprise Storage deletes

## Security

- Admin = `request.auth.token.admin == true` only
- `auditLogs`, `automationJobs`, `adminReviewQueue`: client write denied
- PII masked in `adminSearchUsers`
- Secrets redacted in audit metadata
