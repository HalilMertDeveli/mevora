# QA_STATUS — Hourly Matching Game

**Date:** 2026-08-27 (updated after production-blocker fix)  
**Branch:** `feature/hourly-global-matching-game`  
**Project:** `mevora-d6ed0`  
**Verdict:** **NOT PRODUCTION READY** (deploy blockers fixed; live device/scheduler E2E still open)

| Criterion | Status | Evidence |
|-----------|--------|----------|
| BUILD | **PASS** | `npm run build` (`tsc`) succeeds after restoring `functions/src/automation/*` + `incomingLike` / `likeNotifications` in notifications. |
| DEPLOY | **PASS** | Deployed to `mevora-d6ed0`: 6 hourly functions + Firestore rules. |
| Functions existence | **PASS** | `matchingGameHourlyTick`, `getMatchingGameRound`, `joinMatchingGameRound`, `submitMatchingGameAnswers`, `getMatchingGameResult`, `runMatchingGameRoundNow` listed in `europe-west1`. |
| FIRESTORE | **PASS** (data model) | `matchingGameRounds` created live (`qa_prodready_2026082712` + participants). |
| CF matching path (callable) | **NOT TESTED** | No ADC / App Check client invocation of callables from this agent. |
| SCHEDULER tick execution | **NOT TESTED** | Job exists; no `:00` Istanbul execution observed in logs yet (only CreateFunction). |
| Istanbul timezone (code) | **PASS** | Local harness + round docs use `Europe/Istanbul`. |
| Compatibility math | **PASS** (local + seeded) | Identical `a/b/c` → score **100**, A↔B pair. |
| Two-user device E2E | **MANUAL REQUIRED** | Real Auth users + App Check + 2 devices not run. |
| Discover / Messaging / Legacy 3-min regression | **NOT TESTED** (live) | Local Flutter relationship suite PASS; readiness fallback added. |
| Backend readiness guard | **PASS** (unit) | `not-found` → fall back to legacy dwell; `hourlyBackendReady=false`. |
| Catalog untouched | **PASS** | No catalog diffs. |

## What was fixed this session

1. Restored missing `functions/src/automation/*` from commit `a1188dc`.
2. Extended `FcmTypes.incomingLike` + `PushPrefKey likeNotifications`.
3. Deployed hourly functions + rules to `mevora-d6ed0`.
4. Client readiness fallback when hourly CF missing/unavailable.
5. Waiting overlay (prior) + QA harness scripts.

## Remaining blockers for PRODUCTION READY

1. Two real devices / Auth QA users through callables (App Check).
2. Observe live `matchingGameHourlyTick` at Istanbul `:00` (or admin-invoked CF matching with proof in logs).
3. Live Discover / messaging / legacy dwell regression on a build with flag ON + backend UP.
