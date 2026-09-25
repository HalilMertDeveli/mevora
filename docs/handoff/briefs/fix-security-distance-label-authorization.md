# Brief — `fix/security-distance-label-authorization`

**Source:** Agent B, finding F-02 · **Severity:** CRITICAL
**Base:** `origin/main` @ `6952079857533cfd4a3f407888a856d937c49e7a`
**Worktree:** `D:\Mevora-worktrees\security-distance-label`
**Classification:** `CONTROLLED_PARALLEL`

## Problem

`getDistanceLabel` (`backend.ts:553-577`) returns a distance in km for **any** `otherUid`,
with no match, relationship or block check. `userLocation` is freely client-writable
(`firestore.rules:490-503`), so an attacker can move their own position at will and call the
function repeatedly.

Three measurements from chosen positions trilaterate any user's location. On a dating app this
is the highest real-world-harm finding in the audit, and it is also the narrowest fix.

Read the full finding in `AUDIT-FIREBASE-SECURITY.md` on `audit/firebase-security` (`56063ff`).

## Goal

Authorize the call. A distance should only be returned where the caller is entitled to it, and
the result should not be precise enough to trilaterate.

Consider both halves: the missing authorization check, and whether the returned precision
should be bucketed/fuzzed so repeated calls cannot be triangulated even by an entitled caller.

## File ownership

```
PRIMARY   functions/src/**  (the getDistanceLabel callable and its helpers)
SHARED    firestore.rules   — only if location write rules must change; minimal diff, report it
DO NOT    lib/features/chat/**, functions/src/matching/**, onboarding.ts
TOUCH     anything Agent A owns (see the master handoff)
```

## Dependencies

```
BLOCKED BY    NONE
BLOCKS        NONE
PARALLEL OK   Agent A; fix/security-profile-photos-server-authority; perf/discovery-history-reads
NOT PARALLEL  Any other task editing the same callable
```

Note: `perf/discovery-history-reads` also works in `backend.ts`. Different functions, but the
same file — coordinate, keep diffs tight, and expect a textual conflict if both land close
together.

## Test

Add a test proving a non-matched, non-related caller gets no usable distance for a stranger.
If precision is bucketed, assert that repeated calls from different positions do not converge
on a point.
