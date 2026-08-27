# QA_REPORT — Hourly Matching Game Production Readiness

**Date:** 2026-08-27 (Europe/Istanbul context)  
**Scope:** Independent production QA of Hourly Matching Game on branch `feature/hourly-global-matching-game`  
**Firebase project inspected:** `mevora-d6ed0`  
**Final decision:** **NOT PRODUCTION READY**

---

## 0. Honesty policy

Anything not executed against live Firebase / devices / scheduler is marked **NOT TESTED** or **MANUAL REQUIRED**. Unit-test green ≠ production green.

---

## 1. Code & catalog analysis

### Present implementation

| Area | Location | Notes |
|------|----------|-------|
| Pure engine | `functions/src/hourlyMatchingGameEngine.ts` | Ordinal a/b/c similarity, top-K=20, greedy 1:1, Istanbul round ids |
| CF / scheduler | `functions/src/hourlyMatchingGame.ts` | Tick `0 * * * *` `Europe/Istanbul`; callables; admin `runMatchingGameRoundNow` |
| Exports | `functions/src/index.ts` | All six symbols exported |
| Rules | `firebase/firestore.rules` | `matchingGameRounds` client read-only |
| Flutter | relationship config/controller/repo/datasources/UI | Hourly default ON |
| Docs | `docs/HOURLY_MATCHING_GAME.md` | Matches code intent |

### Question catalog

```text
git diff … -- lib/features/relationship/data/catalog/  → empty
```

**PASS** — questions/options/order not modified.

---

## 2. Firebase deployment control

### CLI / project

- Firebase CLI via `npx firebase-tools@latest` **15.28.1**
- Auth user present; project `mevora-d6ed0` selected
- `.firebaserc` aliases: default/development=`mevora-d6ed0`, staging=`mevora-staging`, production=`mevora-production`

### Full TypeScript build — **FAIL**

```text
src/backend.ts → Cannot find module './automation/cleanup.js'
src/deleteAccount.ts → Missing ./automation/jobs.js, types.js, tasksEnqueue.js
src/backend.ts → incomingLike / likeNotifications type errors
```

### Deploy dry-run — **FAIL**

```text
Error: Functions codebase could not be analyzed successfully
Cannot find module './automation/cleanup.js' (from lib/backend.js)
```

**Conclusion:** Hourly Matching Game **cannot be deployed** until the pre-existing functions build break is fixed. This is a **hard production blocker**, not a documentation footnote.

### Live deployed functions

`firebase functions:list` / MCP `functions_list_functions` — **none** of:

- `matchingGameHourlyTick`
- `getMatchingGameRound`
- `joinMatchingGameRound`
- `submitMatchingGameAnswers`
- `getMatchingGameResult`
- `runMatchingGameRoundNow`

are present among ~40 deployed callables/schedulers.

### Firestore data

Top-level collections on `(default)` include `users`, `profiles`, `matches`, …  
**`matchingGameRounds` is absent** (no live rounds).

---

## 3. Istanbul timezone (local engine — PASS)

Harness verified (UTC instants → Istanbul wall clock):

| Instant (UTC) | Istanbul | Round id |
|---------------|----------|----------|
| 07:59Z | 10:59 | `…10` |
| 08:00Z | 11:00 | `…11` |
| 08:01Z | 11:01 | `…11` |
| 08:59Z | 11:59 | `…11` |
| 09:00Z | 12:00 | `…12` |
| 09:01Z | 12:01 | `…12` |
| 20:59Z → 21:00Z | 23:59 → 00:00 next day | wrap OK |

Format: `YYYYMMDDHH`. Client countdown uses `serverNowMs` / `closesAtMs` from callable payload (by design).

**Live scheduler tick:** **NOT TESTED** (function not deployed).

---

## 4–12. Matching behavior (local engine)

| Scenario | Result | Status |
|----------|--------|--------|
| A=abc B=abc → score 100 | Matched | PASS (local) |
| aaa vs aaa = 100 | OK | PASS |
| aaa vs bbb = 50 | OK | PASS |
| aaa vs ccc = 0 | OK | PASS |
| Formula `1-|ord|/2` | OK | PASS |
| 3 users, A-B exact preferred | 1:1, C unmatched | PASS (local) |
| Single / empty pool | 0 matches | PASS (local) |
| Repeat penalty 15 with alternative | Avoids prior `A|B` | PASS (local) |
| Geographic distance between candidates | **Not in engine** | **WARNING** |
| top-K=20 @ n=500 | ~30 pairs / ~60 matched | **WARNING** (sparsity) |

### ALGORITHM IMPROVEMENT RECOMMENDATION (do not change yet)

1. **Greedy + top-K is a heuristic**, not maximum-weight matching. Do not document as globally optimal.
2. **Top-K hub effect:** popular users consume edges; many compatible users can remain unmatched (observed: 500 → 30 pairs).
3. **No geo / hard preference filters** in hourly engine — only answer snapshots. Product priority list (personality → relationship filters → geo) is **partially unmet**.
4. Recommended follow-ups (separate change request): blossom/MWPM or auction matching on filtered candidate graph; inject eligibility + geo as soft rank keys after personality; monitor unmatched rate.

---

## 13–15. Client / late join / match propagation

| Item | Status |
|------|--------|
| Late join after MATCHING/COMPLETED | Code rejects submit (`round-closed`) | Code review PASS; **runtime NOT TESTED** |
| Waiting UI after submit | Was **missing** (silent Discover) | **Fixed in QA** with `MatchingGameWaitingCard` |
| Result → Matches list → chat | Depends on `matches/{id}` write in CF | **NOT TESTED** live |
| Two real devices | — | **MANUAL REQUIRED** |

---

## 16. Regression

Normal Discover / like / relationship completeRelationshipTest / messaging / block / unmatch: **NOT TESTED** in this session against live backends.

Risk note: Flutter default `hourlyGlobalMatchingGame = true` **turns off** dwell offers. Without deployed hourly CF, personality-game UX is effectively dead in a build that includes this flag.

---

## 17–20. Security / idempotency / duplicates

| Check | Status |
|-------|--------|
| Rules syntax | PASS (`firebase_validate_security_rules`) |
| Client cannot write scores/participants | Intended by rules; **runtime probe NOT TESTED** |
| Duplicate submit short-circuit | Code returns `alreadySubmitted` | **NOT TESTED** live |
| Scheduler double-run lock | Transaction → MATCHING then COMPLETED | **NOT TESTED** live |

---

## 21. Failure recovery

Network drop mid-submit, CF timeout, app kill mid-poll: **NOT TESTED**.

---

## 22. Performance (local CPU only)

| n | optimizeMatches ms (this host) | matches |
|---|--------------------------------|---------|
| 10 | 1 | 5 |
| 50 | 4 | 24 |
| 100 | 11 | 30 |
| 500 | 204 | 30 |

Firestore read/write cost for live rounds: **NOT TESTED**.

---

## 23. Doc vs reality gaps (`docs/HOURLY_MATCHING_GAME.md`)

| Doc claim | Reality |
|-----------|---------|
| Scheduler creates rounds hourly | Code ready; **not deployed** |
| Clients call get/join/submit/result | Client wired; **callables missing in prod** |
| Top-K + greedy | Accurate — doc correctly implies heuristic |
| Global optimal wording avoided | Good |
| Geo / hard filters | Doc silent; product brief expected them — **gap** |

---

## 24. Production readiness scorecard

See `QA_STATUS.md`.

**Overall: NOT PRODUCTION READY**

---

## 25. Five answers (required)

### 1. Hourly Matching Game gerçekten production'a hazır mı?

**Hayır.** Functions build kırık, hourly callables/scheduler deploy edilmemiş, `matchingGameRounds` yok, 2 kullanıcı E2E yok.

### 2. Gerçek iki kullanıcıyla test edildi mi?

**Hayır.** **MANUAL REQUIRED / NOT TESTED.**

### 3. İstanbul saat başı scheduler gerçekten doğrulandı mı?

**Kod seviyesinde timezone PASS; canlı scheduler NOT TESTED / WARNING.** Deploy yok.

### 4. Matching algoritmasında şu anda bilinen ciddi bir problem var mı?

**Kritik math hatası yok** (local). **Ciddi kalite riskleri var (WARNING):** top-K+greedy unmatched oranı; geo yok; max-weight değil. Algoritma değiştirilmedi — rapor önerisi.

### 5. Manuel olarak yapman gereken testler?

1. Fix `functions` build (`automation` + `backend.ts`), deploy hourly functions + rules to staging first.  
2. Create `QA_USER_A/B/C` (clearly tagged), same round, identical answers → expect match + chat.  
3. Call `runMatchingGameRoundNow` (admin/emulator) without waiting for hour.  
4. Observe one real `matchingGameHourlyTick` at Istanbul `:00` (logs: created / matching completed).  
5. Late-join after COMPLETED; duplicate submit; two devices; Discover/chat regression.  
6. Cleanup QA users/docs after test.

---

## 26. Fixes applied during this QA (small, safe)

1. **Waiting overlay** when `waitingForRoundResult` (prevents silent post-submit UX).  
2. Local **QA harness** `functions/test/hourlyMatchingGameQa.harness.cjs`.  
3. This report + `QA_STATUS.md`.

**Not changed:** matching algorithm, top-K, penalty, timezone, round architecture, question catalog.

---

## 27. Next engineering order (recommended)

1. Restore automation modules / fix `tsc` (unblocks all CF deploys).  
2. Deploy hourly package to **staging**.  
3. Staging 2-user E2E + scheduler smoke.  
4. Only then production deploy + store build with hourly flag ON.
