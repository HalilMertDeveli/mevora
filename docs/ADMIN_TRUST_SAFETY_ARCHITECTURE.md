# MEVORA Admin, Trust & Safety and Moderation Platform

The operational control plane for staff: user lookup, cases, reports, photo
and humor moderation, sanctions, identity-verification review, support,
automation review, appeals, audit, and staff management.

It is a **separate application with a separate trust boundary**. The dating
app gains no admin capability, the public support site (`mevora-support-web`)
stays public, and the admin console holds no database credential.

---

## 1. Architecture

```
 Staff browser ──HTTPS──▶ mevora-admin-web (ASP.NET Core 8, Razor Pages, BFF)
                           │  session cookie → server-side ticket (tokens stay on the server)
                           │  CSRF, CSP, rate limits, permission-gated pages
                           │
                           │ POST /{command}  {"data": …}
                           │   Authorization: Bearer <staff Firebase ID token>
                           │   x-mevora-admin-bff: <shared secret>
                           │   x-request-id: <correlation id>
                           ▼
                 Cloud Functions  functions/src/admin  (explicit commands)
                           │  authorizeAdminRequest → rate limit → parse → handler
                           │  transaction: state change + moderationAction + audit event
                           ▼
                 Firestore / Auth / Storage (Admin SDK)
```

| Layer | Owns | Never does |
|---|---|---|
| `mevora-admin-web` | UI, staff session, form validation, CSRF | Read or write Firestore; hold a service account; decide authorisation |
| `functions/src/admin` | Authorisation, business rules, transactions, audit | Offer a generic write; read chat content |
| Existing modules | Photo pipeline, humor moderation, identity store, automation runner | — (reused, not duplicated) |

The admin web depends on no Firebase server library (enforced by a test).

### Backend layout

```
functions/src/admin/
  auth/          permissions.ts · roles.ts (role → permission map) · adminAuthorization.ts
  audit/         auditTypes.ts · auditService.ts (append-only)
  cases/         caseTypes.ts (state machine) · caseService.ts · caseQueries.ts
  users/         searchUsers.ts · getUserOverview.ts · getUserSafetyTimeline.ts · accountActions.ts · userLookup.ts · userCards.ts
  reports/       reportPriority.ts · reportIntake.ts · reportQueue.ts
  photos/        photoReview.ts
  humor/         humorReview.ts
  support/       supportService.ts
  verification/  verificationReview.ts
  automation/    manualReviewQueue.ts
  appeals/       appealService.ts · consumerAppeals.ts (member callables)
  staff/         staffService.ts
  actions/       actionTypes.ts
  command.ts     the one wrapper every command runs through
  commands.ts    the complete command list (name · permission · parser · handler)
  dashboard.ts · retention.ts · accountDeletion.ts · index.ts
```

`commands.ts` **is** the admin surface: reviewing it is reviewing everything
the console can do.

---

## 2. Trust boundaries

1. **Browser → admin web.** HttpOnly, `SameSite=Strict`, `__Host-` session cookie
   pointing at a server-side ticket (`DistributedTicketStore`). Antiforgery on
   every POST. CSP `default-src 'none'; script-src 'self'; style-src 'self'`,
   `frame-ancestors 'none'`, `no-store` on every page, HSTS in production.
2. **Admin web → Functions.** The staff member's own ID token plus the BFF
   shared secret. The secret proves the call came from the admin web's server
   (a stolen staff token alone is refused); it is not authority by itself.
3. **Functions → data.** `authorizeAdminRequest`, in this order:
   BFF credential → token present → `token.admin === true` → second factor used
   (production: always) → `adminStaff/{uid}` exists and `status == active` →
   token `auth_time` after `sessionsValidAfter` → role known → role grants the
   command's permission.

The custom claim is a coarse gate only. The staff record is the authority:
disabling or re-roling a staff member takes effect on their next request, and
their refresh tokens are revoked.

**App Check.** Consumer callables keep `enforceAppCheck`. Admin commands set
`enforceAppCheck: false` because they are called server-to-server by the admin
web, which cannot hold an App Check token (App Check attests an app instance,
not a person). The BFF credential, staff token, MFA, staff record, RBAC and
per-staff rate limits replace it.

---

## 3. Roles and permissions

Single authority: `functions/src/admin/auth/roles.ts`.

| Permission area | support_agent | moderator | senior_moderator | trust_safety_admin | super_admin |
|---|:-:|:-:|:-:|:-:|:-:|
| dashboard, user.read | ✓ | ✓ | ✓ | ✓ | ✓ |
| user.read_sensitive (contact details, audited) | | | | ✓ | ✓ |
| support.* | ✓ | read, escalate | read, escalate | ✓ | ✓ |
| report.*, case.*, photo.*, humor.* | | ✓ | ✓ | ✓ | ✓ |
| case.reassign (take over a held case) | | | ✓ | ✓ | ✓ |
| user.warn, user.suspend | | ✓ | ✓ | ✓ | ✓ |
| user.ban, user.restore | | | ✓ | ✓ | ✓ |
| verification.read / escalate | | ✓ | ✓ | ✓ | ✓ |
| verification.require_reverification | | | ✓ | ✓ | ✓ |
| automation.read | | ✓ | ✓ | ✓ | ✓ |
| automation.review / resolve_sensitive | | | | ✓ | ✓ |
| appeal.read | ✓ | ✓ | ✓ | ✓ | ✓ |
| appeal.create (file for a member) | ✓ | | ✓ | ✓ | ✓ |
| appeal.assign / resolve | | | ✓ | ✓ | ✓ |
| audit.read | | | | ✓ | ✓ |
| admin.manage_staff / manage_roles / maintenance | | | | | ✓ |

Staff guards: nobody acts on their own account or role; roles are granted only
below one's own rank (super admins excepted); **super_admin is never granted
through the console** (`GRANTABLE_ROLES` in roles.ts); an active super admin
cannot be sanctioned; the last active super admin cannot be demoted or disabled.

### Owner and organisation

Production starts with one **owner super admin** and, when needed, one or more
**Trust & Safety admins** who run daily operations (moderation, reports,
users, support, verification review, appeals, photos, automation, audit
reading). The narrower roles stay for when the team grows. There is no
generic "admin" role.

- The owner is `adminStaff/{uid}.isOwner == true` on a `super_admin` record.
  Only `tool/adminBootstrapStaff.cjs --owner` sets it; clients cannot write
  `adminStaff` at all, and no console command sets, clears or acts on it
  (`cannot_modify_owner` for role change, disable, session revoke and
  activation, even from another super admin). There is exactly one owner; the
  tool refuses a second.
- Ownership transfer is deliberately not a console action. If it is ever
  needed it becomes its own command (`adminTransferOwnership`) requiring the
  current owner, a recent MFA sign-in, typed confirmation and an audit event.
- Owner-level permissions (`admin.manage_staff`, `admin.manage_roles`,
  `admin.maintenance`) belong to super_admin only; trust_safety_admin never
  holds them (tested).

### Adding and managing staff

`adminCreateStaff` (manage_staff + manage_roles) takes email, display name and
a grantable role. It creates the Firebase Auth login when none exists, with a
32-byte random password that is never returned, stored or logged, and marks
the address verified (Firebase requires that before MFA enrolment). The admin
web then asks Firebase (`accounts:sendOobCode`, PASSWORD_RESET) to email the
colleague a password-setup link — the super admin never sees a password or a
link. A member's app account cannot become staff (`staff_account_is_member`).
At first console sign-in `adminRecordLogin` forces TOTP enrolment.

The staff console (`/Admin/Staff`, `/Admin/Staff/{uid}`) lists every
colleague (role, status, owner/QA badges, last console sign-in, creator, last
role change) and offers change role, disable / re-enable, end sessions
(`adminRevokeStaffSessions`: `sessionsValidAfter = now` + refresh-token
revocation) and resend password setup (`adminIssueStaffActivation`). The
detail page adds Firebase sign-in facts, enrolled MFA factor kinds (never
secrets) and an activity summary built from one `count()` per activity group
on `adminAuditLog (actorAdminId, action)` plus the last 20 events.

Staff audit events: `ADMIN_CREATED`, `ADMIN_ROLE_CHANGED`, `ADMIN_DISABLED`,
`ADMIN_ENABLED`, `ADMIN_SESSIONS_REVOKED`, `ADMIN_ACTIVATION_ISSUED`
(`ADMIN_GRANTED` remains for bootstrap and historic grants).

The seeded emulator accounts (`super@`, `tsa@`, `senior@`, `moderator@`,
`support@mevora.test`) are **EMULATOR / QA ONLY** role-test identities, marked
`seededFor: "emulator-qa"` and badged in the console. The owner's own QA login
(`halilmertdeveliii@gmail.com`) is seeded only when `SUPER_ADMIN_QA_PASSWORD`
is set; there is no default.

The first super admin is created with `tool/adminBootstrapStaff.cjs` (owner-run).
Every later change goes through the console and is audited.

---

## 4. Collections

All server-owned. Firestore rules deny every client operation, including
clients carrying the admin claim (`firebase/tests/admin.security.emulator.test.mjs`).

| Collection | Purpose |
|---|---|
| `adminStaff/{uid}` | role, status, sessionsValidAfter |
| `moderationCases/{caseId}` (+ `/notes`) | investigations; notes = internal notes and system events |
| `moderationCaseKeys/{hash}` | correlation lock: one open case per key |
| `moderationActions/{actionId}` | every decision taken |
| `adminAuditLog/{eventId}` | append-only audit trail |
| `appeals/{appealId}` | member appeals (owner may read) |
| `supportTickets/{id}/messages` | member-visible support thread (owner may read) |
| `supportTickets/{id}/internalNotes` | staff-only notes (nobody may read directly) |
| `adminUserLookup/{uid}` | folded display name for prefix search (no contact data) |
| `adminRateLimits/{uid_class}` | per-staff rate-limit windows |

Existing collections reused, not moved: `reports`, `supportTickets`,
`users/{uid}/photoModeration`, `humorReports`, `humorModerationQueue`,
`automationJobs`, `adminReviewQueue`, `users/{uid}/verification/identity`.

### Indexes

Every admin query is backed by a composite index in `firebase/firestore.indexes.json`
(35 added): case queues by status/priority/age (with type and assignee
variants), closed cases by resolution time, actions and appeals per member,
audit by actor/target/action, reports by priority, support by status and
assignee, and collection-group indexes on `photoModeration` and `verification`.
Deploy indexes before the functions that use them.

---

## 5. Case model

```
open ──▶ assigned ──▶ in_review ──▶ waiting
  │          │            │            │
  └──────────┴──── resolved / dismissed (terminal) ◀──┘
```

`CASE_TRANSITIONS` in `caseTypes.ts` is the only source of allowed moves.

- **Intake & correlation.** A new report opens or joins the case keyed
  `user_report:{subject}:{reason}`. Different reasons never merge (an
  `underage` report is never swallowed by a `spam` case). Three distinct
  reporters raise priority one level. Photo, humor, verification, support,
  automation and appeal escalations use their own keys.
- **Concurrency.** Every change re-reads the case in a transaction. Two
  moderators claiming at once: one wins, the other gets `case_already_assigned`.
- **Resolution** closes the case's open reports and releases the key, so the
  next report opens a fresh case.
- **Report priority** is set server-side in `reportUser` from the production
  reason whitelist: child_safety (sexual content or behaviour involving a
  minor), underage → critical; harassment, scam, inappropriate
  content → high; fake profile → medium; spam, other → normal.
  `adminBackfillReportPriority` backfills legacy reports.

## 6. Action model

A case is the investigation; an action is a decision. Types: `WARNING`,
`TEMPORARY_SUSPENSION`, `PERMANENT_BAN`, `RESTORE_ACCOUNT`, `SUSPENSION_EXPIRED`,
`PHOTO_APPROVED`, `PHOTO_REJECTED`, `PHOTO_REMOVED`, `REQUIRE_REVERIFICATION`,
`SUPPORT_ESCALATION`, `APPEAL_ACCEPTED`, `APPEAL_REJECTED`.

Actions are never rewritten. Undoing a decision is a new action that points
back (`relatedActionId`); the old one only gains `overturnedByActionId`.

**Idempotency.** High-impact commands take a key minted per rendered form.
The action id is derived from (actor, command, target, key), so a double click
or network retry replays the first result instead of acting twice.

### Account state

`users/{uid}.accountStatus` ∈ `active | suspended | banned | deleted` is
canonical, with `suspendedUntil`, `statusReasonCode`, `statusActionId`,
`statusUpdatedAt`. Legacy `isBanned` / `isSuspended` are mirrored on every
write and still restrict on their own (`effectiveAccountStatus`).

- **Suspension:** Auth untouched. Ends by itself at `suspendedUntil`
  (eligibility checks the time); `adminSuspensionExpirySweep` rewrites the
  stored state and records `SUSPENSION_EXPIRED`.
- **Ban:** Auth account disabled and refresh tokens revoked, after the
  transaction; the outcome is recorded on the action (`authSync`) and a replay
  retries it.
- **Restore:** re-enables Auth only if a ban disabled it.
- **Eligibility:** one guard (`accountGuard.ts`) on discovery, likes, incoming
  likes, boosts, calls, compatibility and engagement callables; message
  creation is refused by rules for a restricted account. Report, block,
  unmatch, delete, export, support and appeal stay available.
- **App:** `AccountStatus.suspended` is read like the backend; a restricted
  member is signed out with the existing suspended message.

---

## 7. Photo moderation

The ledger `users/{uid}/photoModeration/{imageId}` remains the authority.
`adminReviewPhoto` writes through `setPhotoModerationStatus` (ledger first, then
the profile projection); `enforceProfilePhotoModeration` keeps reconciling.
The console never writes `profiles/{uid}.photos`.

- Approve an unpublished photo → published with the pipeline's own
  `publishApprovedPhoto` to the server-only `photos/` prefix.
- Reject → image moved to server-only `moderation/quarantine/{uid}/` (kept for
  the appeal window) and removed from view. Rejecting a published photo is
  `PHOTO_REMOVED`. A rejected photo cannot be approved again.
- Two reviewers cannot decide at once (review lock); the lock stores an opaque
  token, because the member can read their ledger.
- Previews are fetched server-side and streamed with `no-store`. No signed URL,
  no public bucket.
- Queues: manual review, reported profiles, retries exhausted, pending too long.

## 8. Verification boundary

The console shows only what MEVORA stores: provider, status, normalised
reason, timestamps, attempt count, a shortened session reference. It never
stores or shows ID images, selfies, liveness video, biometrics, MRZ or raw
provider payloads.

**There is no command that marks a member verified** (tested statically).
`adminRequireReverification` can only remove the badge: it sets the identity
document to `expired`, clears `isVerified` on account and profile, revokes the
current provider session and moves `lastEventAtMs` forward. A late or replayed
webhook from the revoked session is ignored (`session_revoked`). Only a new
session that the provider marks verified sets the badge again.

## 9. E2EE boundary

- No admin command, page or route reads `matches/*/messages`, E2EE keys, or
  decrypts anything (tested statically in `adminCommandSurface.test.cjs` and by
  route tests in the admin web).
- Reports carry `matchId` / `messageId` as references only; the console shows
  them labelled as such.
- No server-side key was added; the ciphertext-only rules are unchanged (rule
  test re-asserts plaintext is refused).
- Future user-disclosed evidence (a member explicitly sharing one selected
  message) would be a new, opt-in report attachment — not part of v1.

## 10. Support integration

Tickets from the app and from `mevora-support-web` keep their shapes. The
console normalises both vocabularies (`Open`/`open`, `Urgent`/`urgent`) and adds
only server-owned fields: `assignedTo`, `firstResponseAt`, `lastSupportReplyAt`,
`resolvedAt`, `resolvedBy`, `priority`, `escalatedAt`, `caseId`.

Replies go to `messages` (member-visible, signed "Mevora Support", no staff
uid); internal notes go to `internalNotes`. Rules now also restrict the app's
ticket creation to exactly the fields the app writes.

Website tickets carry a visitor-typed `userId`; the console marks them
**unverified** and does not join them to a member.

The app does not yet display the reply thread (follow-up); website tickets
are answered by email from the contact address shown on the ticket.

## 11. Appeals

`appeals/{appeal_<actionId>}` — one appeal per decision, within 30 days.
Members use `submitModerationAppeal` / `getMyModerationStatus` (App Check
enforced; work while suspended). Banned members cannot sign in, so their
appeals arrive via the support site and staff file them (`adminOpenAppeal`).

Deciding: the original decider cannot review their own decision (super admins
excepted). Accept → `APPEAL_ACCEPTED`, plus `RESTORE_ACCOUNT` when the
suspension/ban is still in force. Accepting a re-verification appeal never
makes anyone verified.

## 12. Audit

`adminAuditLog` is written only with `create` inside the same transaction as
the change it records. There is no update or delete path besides the
scheduled retention sweep. Events include `ADMIN_LOGIN`,
`SENSITIVE_PROFILE_VIEWED`, case, sanction, photo, humor, verification,
support, automation, appeal and staff events.

The console filters the log by any combination of staff member, staff role,
event, target type, target id, case and a UTC date range. The most selective
equality filter and the date range run in Firestore (field + `createdAt`
composite indexes); the remaining filters apply to that ordered stream, and a
request reads at most 500 events (`AUDIT_SCAN_CAP`) — a page that stops early
says so and its cursor continues exactly where the scan ended.

Metadata is scrubbed: passwords, tokens, OTPs, secrets, authorization headers,
message bodies, identity documents and raw payloads are dropped; free text
(internal notes, justifications) is reduced to its length; emails/phones in
strings are redacted.

Structured logs carry command, actor uid, outcome, duration and the request id
(also stored on the audit event).

### App Control

The owner's controlled switches for the mobile app (`/AppControl`). It is
not a database editor. It exposes four named, audited changes:

| Command | Changes | Audit |
|---|---|---|
| `adminUpdateMaintenanceMode` | maintenance on/off + optional plain-text message | `APP_MAINTENANCE_ENABLED` / `_DISABLED` |
| `adminUpdateMinimumVersion` | per platform: minimum (blocking), recommended (soft), store link (Play / App Store hosts only) | `APP_MIN_VERSION_CHANGED` |
| `adminUpdateFeatureSwitch` | `boost`, `calls`, `spotify`, `humorLab`, `picks` on/off + reason | `APP_FEATURE_SWITCH_CHANGED` |
| `adminUpdateAnnouncement` | plain-text title ≤80, message ≤280, info/warning, start, required end ≤31 days | `APP_ANNOUNCEMENT_CHANGED` |

- Permissions: `app_control.read` (trust_safety_admin, super_admin), `app_control.write` (super_admin only).
- Every change carries `expectedRevision` and an idempotency key. A stale revision gets `conflict`; a replay returns the first result.
- One transaction writes `appOperationsConfig/current` (server-only, with the actor), the public projection `appOperationsConfig/public` (world-readable, no actor), the idempotency marker `appOperationsConfigWrites/*` and the audit event. Audit metadata holds previous and new values. Announcement text is recorded as lengths only.
- The health panel shows real probes made on page load (Firestore read, Auth `getUser`, Storage `exists`) plus environment and revision. Crash and analytics services are not connected, so nothing is invented for them.

**Server enforcement** (`functions/src/appOperations/appOperationsGate.ts`):
- Maintenance, or a feature switched off, refuses the guarded callables with `unavailable` / `maintenance` or `feature_disabled`, so an old app build cannot bypass it. The public doc is cached for 15 s per instance, and an unreadable config fails open.
- Guarded:
  - `activateBoost`
  - `createVideoCall`
  - `spotifyLinkMusic` and `syncSpotifyTaste`
  - the four Humor Lab callables
  - `getMevoraPicks`
  - `getDiscoveryCandidates`, `recordDiscoveryDecision` and `recordSwipe` (maintenance only)
- Never guarded:
  - account deletion, data export, support, report / block / unmatch and appeals
  - `verifyBoostPurchase`: a paid purchase is always credited
  - `spotifyCompleteAuth`: Spotify sign-in never locks a member out

## 13. Retention and account deletion

| Data | Policy (days) | On account deletion |
|---|---|---|
| `adminAuditLog` | 730 | kept (uid references only) |
| `moderationActions` | 1095; the action behind a live ban is kept | kept |
| closed `moderationCases` + notes | 730 after closing | open cases closed as `subject_deleted` |
| resolved `appeals` | 730 | deleted (member's own words) |
| support thread / internal notes | with the ticket | deleted with the member's tickets |
| quarantined photos | 90 | deleted |
| `adminUserLookup` | — | deleted |
| `adminRateLimits` | 2 (always enforced) | — |

These horizons are a legal/business decision. `adminRetentionSweep` runs daily
in **dry-run** (counts and logs) until the owner confirms them and sets
`ADMIN_RETENTION_ENFORCE=true` on the functions.

Existing behaviour noted, not changed here: `deleteUserAccount` deletes reports
filed *against* the deleted member. Cases keep reason codes and counts, but the
report text is gone. Worth a policy review (ban evasion via deletion).

---

## 14. Deployment

Owner-run, from a `main` worktree, after approval. Nothing is deployed by this
change.

1. **Billing** — Cloud Billing must be re-enabled on `mevora-d6ed0` first.
2. **Identity Platform MFA** — upgrade Firebase Auth to Identity Platform and
   enable TOTP MFA for the project (Console → Authentication → Sign-in method
   → Multi-factor, or the Admin SDK `projectConfigManager`). Staff are forced
   to enrol TOTP on first console sign-in.
3. **Secret** — `firebase functions:secrets:set ADMIN_BFF_SHARED_SECRET --project mevora-d6ed0`
   (32+ random characters); the same value goes to the admin web's
   `AdminWeb__BffSharedSecret`.
4. **Rules and indexes** —
   `firebase deploy --project mevora-d6ed0 --only firestore:rules,firestore:indexes`
   and wait for the indexes to finish building.
5. **Functions** — deploy only the new/changed names (`--only functions:adminGetDashboard,…`),
   never a bare `firebase deploy` (see the orphan-function note in the deploy
   docs). The changed consumer callables (`reportUser`, `getIncomingLikes`,
   `activateBoost`, video-call callables, `getDistanceLabel`, compatibility
   callables, `recordProfileEngagement`, `deleteUserAccount`,
   `identityVerificationWebhook`) must ship together with the admin set.
6. **Admin web** — host privately (Cloud Run with IAP or an allow-listed
   ingress recommended), HTTPS only, environment `Production`, with
   `AdminWeb__WebApiKey`, `AdminWeb__FunctionsBaseUrl`,
   `AdminWeb__BffSharedSecret`. For more than one instance, register a shared
   `IDistributedCache` (e.g. Redis) for sessions.
7. **Owner super admin** — the owner creates their own Firebase Auth login (console → Authentication → Add user, choosing the password themselves), then runs `node tool/adminBootstrapStaff.cjs --project mevora-d6ed0 --email <owner email> --role super_admin --owner --confirm`. TOTP enrolment is forced at first console sign-in. Colleagues are then added from `/Admin/Staff`.
8. **Backfills** (console, super admin) — Admin → maintenance commands:
   `adminBackfillReportPriority`, `adminRebuildUserLookup` (paged).

Rollback: disable staff in the console, or set every `adminStaff` status to
`disabled`; redeploy the previous functions revision; the admin collections are
inert without the commands. The rules changes are additive except the
tightened support-ticket create allow-list and the restricted-account message
rule.

## 15. Security checklist

- [x] No client can read or write admin collections (rules + emulator tests)
- [x] Authorisation from `adminStaff` + roles.ts on every command; claims are hints
- [x] MFA required in production; emulator relaxation cannot apply outside the emulator (tested)
- [x] BFF credential required; unset secret fails closed
- [x] No generic write command; parsers ignore unknown fields
- [x] Idempotent high-impact actions; transactional state + action + audit
- [x] Append-only, scrubbed audit log
- [x] Sensitive contact reveal needs permission + justification, is audited
- [x] No chat reading, no E2EE key access, no verification override
- [x] Photo decisions through the ledger; private previews; quarantine
- [x] CSRF, strict CSP, no-store, HSTS, secure cookies, rate limits
- [x] No service account or secret in the admin web or its pages
- [ ] Owner: Identity Platform TOTP, secret, private hosting, first super admin

## 16. Manual QA (emulator)

Setup is in `mevora-admin-web/README.md`. Seeded staff: `super@`, `tsa@`,
`senior@`, `moderator@`, `support@mevora.test`; members `qa_ts_*`.
`tool/adminConsoleSmoke.cjs` automates the checklist below end to end.

| # | Check |
|---|---|
| T1 | Staff sign-in works (emulator banner shows MFA not used) |
| T2 | A member account (`qa_ts_active@mevora.test`) is refused |
| T3 | Dashboard counters load |
| T4 | Search by name (`ruzgar`), exact email, UID |
| T5 | User detail shows account, profile, safety, timeline, verification |
| T6 | Moderator warns |
| T7 | Moderator suspends (preset and custom length) |
| T8 | Moderator has no ban control; a forced POST is refused |
| T9 | Senior bans; the Auth account is disabled |
| T10 | Senior restores; history keeps the ban, marked overturned |
| T11 | Report queue: underage first, harassment reports grouped |
| T12 | Claiming a case; a second moderator is refused |
| T13 | Closing a case closes its reports |
| T14 | Photo manual review: preview, approve |
| T15 | Photo reject needs a reason; a decided photo cannot be decided again |
| T16 | Support reply (member-visible) vs internal note (staff-only) |
| T17 | Verification queue shows provider status only |
| T18 | No "mark verified" control anywhere |
| T19 | Require re-verification removes the badge |
| T20 | Automation manual review shows per-kind actions only |
| T21 | Appeal accepted → suspension lifted by a restore action |
| T22 | Safety timeline shows the new events |
| T23 | Audit log lists the session's actions |
| T24 | The app still works (Discover, likes, chat) for active members |
| T25 | No console route shows private conversations |
| T26 | Disabling a staff member ends their session on the next click |
| T27 | Contact reveal requires a justification and is audited |
