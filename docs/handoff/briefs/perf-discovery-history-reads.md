# Brief — `perf/discovery-history-reads`

**Source:** Agent C, finding PC-01 · **Severity:** CRITICAL (performance / cost)
**Base:** `origin/main` @ `6952079857533cfd4a3f407888a856d937c49e7a`
**Worktree:** `D:\Mevora-worktrees\discovery-history-reads`
**Classification:** `CONTROLLED_PARALLEL`

## Problem

Every discovery call rebuilds the user's entire history before a single candidate is
evaluated, at roughly `O(S + P + M + B + G)`:

- `backend.ts:180-181` — `likes.where("fromUserId","==",uid).get()` and
  `users/{uid}/passedUsers.get()`, with no limit, cursor or window.
- `backend.ts:107-111` — `loadBlockedUserIds` adds three more unbounded reads.
- `loadActiveMatchPartnerIds` adds a fourth.

Measured growth: ~50-swipe user ≈ 65 reads; ~5,000-swipe user ≈ 7,000. The client fetches
roughly one call per 12 cards, so a 100-card session replays ≈ 56,000 history reads.

## Read this first — a common misconception

The forward candidate scan is **already properly paginated** (pageSize 40, maxPages 3–4, real
cursor, batched hydration). That work is done; do not redo it. The bounding was applied to the
scan and never to the backward history reconstruction — that untouched half is this task.

Full analysis in `AUDIT-PERFORMANCE-COST.md` on `audit/performance-cost` (`f4f3a5b`).

## Goal

Bound the history reconstruction so per-call cost does not grow with account lifetime.

## File ownership

```
PRIMARY   functions/src/**  (discovery backend, history/block/match loaders)
SHARED    firestore.rules   — only if new indexes or shapes require it; minimal diff, report it
DO NOT    lib/features/chat/**, onboarding.ts, firestore.rules unless required
TOUCH     anything Agent A owns (see the master handoff)
```

## Dependencies

```
BLOCKED BY    NONE
BLOCKS        PC-06 (escalation cascade) benefits from this landing first
PARALLEL OK   Agent A; both security branches
NOT PARALLEL  PC-02 / PC-03 / PC-04 — they edit the same loop and will conflict textually.
              PC-13 reshapes the query they sit inside and must land after them.
```

`fix/security-distance-label-authorization` also touches `backend.ts` — different functions,
same file. Coordinate.

## Test

Assert reads per discovery call stay bounded as history grows: seed an account with a large
like/pass history and show the call does not scale with it. A two-device acceptance run will
**not** catch a regression here — fresh accounts have `S = P = M ≈ 0`.

## Do not

Do not bundle PC-02, PC-03, PC-04 or PC-06 into this branch. One finding, one branch.
Do not speculatively optimize anything the audit did not measure.
