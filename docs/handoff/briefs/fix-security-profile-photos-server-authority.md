# Brief — `fix/security-profile-photos-server-authority`

**Source:** Agent B, finding F-01 · **Severity:** CRITICAL
**Base:** `origin/main` @ `6952079857533cfd4a3f407888a856d937c49e7a`
**Worktree:** `D:\Mevora-worktrees\security-profile-photos`
**Classification:** `CONTROLLED_PARALLEL`

## Problem

The client holds authority over its own photo moderation state.

- `firestore.rules:443-461` — `profiles/{uid}.photos[]` is written without validating the
  entries, so a client can set `moderationStatus` and `downloadUrl` to anything.
- `firebase_profile_data_source.dart:145-156` — the client writes those fields verbatim.
- `onboarding.ts:119-151` — `completeOnboarding` trusts that state and sets
  `profileModerationStatus: 'approved'` and `isDiscoverable: true`.

A user can self-approve arbitrary remote images; the moderation pipeline never runs.

Read the full finding in `AUDIT-FIREBASE-SECURITY.md` on `audit/firebase-security`
(`56063ff`) before starting — it has the complete call chain.

## Goal

Move photo moderation authority to the server. A client write must not be able to decide that
a photo is approved or that a profile is discoverable.

## File ownership

```
PRIMARY   functions/src/**   (onboarding, photo moderation)
          firestore.rules    (photos[] validation)
SHARED    firestore.rules    — high-conflict; keep the diff minimal, report it
DO NOT    lib/features/chat/**, lib/features/discovery/**, functions/src/matching/**
TOUCH     anything Agent A owns (see the master handoff)
```

`firestore.rules` is also modified-uncommitted in the user's worktree — expect a merge
conflict there and flag it in the final report.

## Dependencies

```
BLOCKED BY    NONE
BLOCKS        NONE (but relates to fix/security-photo-url-revocation, B F-03)
PARALLEL OK   Agent A; fix/security-distance-label-authorization; perf/discovery-history-reads
NOT PARALLEL  Any other task editing firestore.rules or onboarding.ts
```

## Test

Extend `test/security/` and `firebase/tests/` with rules tests proving a client cannot set
`moderationStatus` or flip `isDiscoverable` directly. Run the existing rules suite — the audit
noted some tests assert behaviour the rules do not actually enforce, so check for tests that
pass today for the wrong reason.

## Do not

Do not bundle F-03 (photo URL revocation) into this branch. One finding, one branch.
