# QA_REPORT — Hourly Matching Game (post blocker-fix)

**Date:** 2026-08-27  
**Project:** `mevora-d6ed0`  
**Branch:** `feature/hourly-global-matching-game`  
**Final decision:** **NOT PRODUCTION READY**

---

## Executive summary

Production **build/deploy blockers are resolved**. All six hourly matching Cloud Functions and Firestore rules are **live** on `mevora-d6ed0`.  

However this QA still **cannot** claim full production readiness: **two-device callable E2E**, **live scheduler tick**, and **live Discover/messaging/legacy regression** remain **NOT TESTED / MANUAL REQUIRED**.

---

## 1. Build blocker — FIXED

### Root cause

- `backend.ts` / `deleteAccount.ts` imported `./automation/*` modules that were missing from the tree (present only in snapshot commit `a1188dc`).
- `FcmTypes.incomingLike` and `PushPrefKey` `"likeNotifications"` used by `backend.ts` but not defined in `notifications.ts`.

### Fix

- Restored `functions/src/automation/**` from `a1188dc`.
- Added `incomingLike` FCM type + copy + `likeNotifications` pref + optional `idempotencyKey` on `sendUserPush`.

### Result

```text
cd functions && npm run build   → exit 0
```

---

## 2. Deploy — PASS

```text
firebase deploy --only \
  functions:matchingGameHourlyTick,\
  functions:getMatchingGameRound,\
  functions:joinMatchingGameRound,\
  functions:submitMatchingGameAnswers,\
  functions:getMatchingGameResult,\
  functions:runMatchingGameRoundNow,\
  firestore:rules \
  --project mevora-d6ed0
→ Deploy complete!
```

Required `functions/.env.mevora-d6ed0` (SPOTIFY/SUMSUB string params) for non-interactive param resolution. File is gitignored.

### Functions existence — PASS

Confirmed via `firebase functions:list` / MCP:

| Function | Trigger |
|----------|---------|
| matchingGameHourlyTick | scheduled |
| getMatchingGameRound | callable |
| joinMatchingGameRound | callable |
| submitMatchingGameAnswers | callable |
| getMatchingGameResult | callable |
| runMatchingGameRoundNow | callable |

---

## 3. Firestore — PASS (collection + QA seed)

Created live:

- `matchingGameRounds/qa_prodready_2026082712` (`timezone: Europe/Istanbul`, later `COMPLETED`)
- participants `qa_hour_user_a` / `qa_hour_user_b` with identical `rq_001=a,rq_002=b,rq_003=c`
- round match doc score **100**, mutual `partnerId`, shared `matchId`

Engine verification on the same answer maps:

```json
{"score":100,"pairCount":1,"pair":{"userA":"qa_hour_user_a","userB":"qa_hour_user_b","score":100,"exactAligned":3}}
```

**Honesty:** Match documents were written via **Admin/MCP** after local `optimizeMatches`, **not** by invoking the deployed `runMatchingGameRoundNow` / scheduler. CF matching execution path remains **NOT TESTED**.

Cleanup: docs tagged `qaTag: hourly-matching-game` — delete when finished.

---

## 4. Scheduler — NOT TESTED (execution)

- Scheduler **resource exists** after deploy.
- Logs show **CreateFunction** only; no `[HOURLY_GAME]` runtime tick yet.
- Next natural Istanbul hour after deploy was not waited out in this session.

---

## 5. Safety: backend readiness guard — PASS (unit)

If `getMatchingGameRound` fails with `not-found` / `unavailable` / `unimplemented`, controller sets `hourlyBackendReady=false` and **falls back to legacy Discovery dwell**.  

Prevents shipping hourly Flutter flag with a dead personality game when CF missing.

---

## 6. Scorecard

| Area | Status |
|------|--------|
| Build | **PASS** |
| Deploy | **PASS** |
| Functions existence | **PASS** |
| Firestore round model | **PASS** |
| Scheduler (live `:00` tick) | **NOT TESTED** |
| Istanbul timezone (code) | **PASS** |
| Two-user device E2E | **MANUAL REQUIRED** |
| Compatibility (engine) | **PASS** |
| CF callable matching | **NOT TESTED** |
| Discover regression (live) | **NOT TESTED** |
| Messaging regression (live) | **NOT TESTED** |
| Legacy 3-minute regression (live) | **NOT TESTED** (unit path still covered with `hourlyGlobalMatchingGame: false`) |

---

## 7. Five answers

1. **Production ready?** **No** — deploy OK, end-to-end user proof incomplete.  
2. **Two real users/devices?** **No** — **MANUAL REQUIRED**.  
3. **Istanbul `:00` scheduler observed?** **No** — **NOT TESTED** (job deployed only).  
4. **Serious matching math bug?** None found locally; quality caveats (top-K greedy, no geo) unchanged.  
5. **Your checklist (max 5):** see below.

---

## 8. Manual checklist (max 5)

1. On two devices, login as tagged QA users (onboarding complete), open Discover at the same Istanbul hour, join round, answer **identical** `a/b/c` set.  
2. After submit, wait for next hour **or** call `runMatchingGameRoundNow` as **admin** (App Check + admin claim); confirm mutual result + Matches list + chat.  
3. Watch Cloud Logging for `[HOURLY_GAME]` on `matchingGameHourlyTick` at the next Istanbul `:00`.  
4. With backend UP: smoke Discover like, open chat, and (debug) `hourlyGlobalMatchingGame: false` dwell offer still works.  
5. Delete `matchingGameRounds` / Auth docs with `qaTag=hourly-matching-game` (incl. `qa_prodready_2026082712`).

---

## 9. Decision

### NOT PRODUCTION READY

Ship only after manual checklist items 1–3 succeed. Build/deploy gate is green.
