# QA_STATUS — Hourly Matching Game

**Date:** 2026-08-27  
**Branch:** `feature/hourly-global-matching-game`  
**Project checked:** `mevora-d6ed0`  
**Verdict:** **NOT PRODUCTION READY**

| Criterion | Status | Evidence |
|-----------|--------|----------|
| BUILD | **FAIL** | `functions` `tsc` fails: missing `./automation/*`, `backend.ts` type errors. Deploy dry-run fails (`Cannot find module './automation/cleanup.js'`). |
| TESTS (unit/local) | **PASS** | Flutter relationship **43/43**. Engine **10/10**. QA harness **14/14** (math/TZ/1:1/repeat/perf). `flutter analyze` clean. |
| FIREBASE (live functions) | **FAIL** | `functions:list` has **no** `matchingGameHourlyTick`, `getMatchingGameRound`, `join…`, `submit…`, `getMatchingGameResult`, `runMatchingGameRoundNow`. |
| SCHEDULER | **NOT TESTED** | Function not deployed; production cron never observed. |
| TIMEZONE (code) | **PASS** (local) | Engine harness: 10:59/11:00/11:01, 11:59/12:00/12:01, midnight wrap → `YYYYMMDDHH` Istanbul. |
| TIMEZONE (live scheduler) | **WARNING / NOT TESTED** | Live Cloud Scheduler tick not verified. |
| SECURITY (rules syntax) | **PASS** | `firebase_validate_security_rules` OK. Client write denied by rules source review. |
| SECURITY (runtime rules E2E) | **NOT TESTED** | No Rules Unit Test / emulator denial probes run. |
| MATCHING (engine math) | **PASS** (local) | aaa/aaa=100, aaa/bbb=50, aaa/ccc=0; formula matches docs. |
| MATCHING (geo ranking) | **WARNING** | Engine has **no** geographic distance — only answer ordinal distance. Spec priority #4 not implemented. |
| MATCHING (top-K quality) | **WARNING** | Local n=500 → only **30** pairs (~60 users). Top-K+greedy sparsity; not max-weight optimal. |
| CLIENT (unit) | **PASS** | Hourly offer/submit mock path covered; waiting overlay added after QA finding. |
| CLIENT (prod against live CF) | **FAIL / NOT TESTED** | Callables absent → cannot complete live client flow. |
| TWO USER E2E | **MANUAL REQUIRED / NOT TESTED** | No QA_USER_A/B on real Firebase; no two-device run. |
| REGRESSION (Discover/chat) | **NOT TESTED** | Live regression not run this session. |
| PERFORMANCE (engine CPU) | **PASS** (local) | n=10/50/100/500 optimizeMatches: 1/4/11/204 ms on this machine. |
| PERFORMANCE (Firestore R/W) | **NOT TESTED** | No live round. |
| CATALOG UNTOUCHED | **PASS** | `git diff` vs catalog path empty. |

## Blockers (must fix before any prod claim)

1. Restore/fix `functions` build (`automation` modules + `backend.ts` types) so deploy works.
2. Deploy hourly matching functions + Firestore rules for `matchingGameRounds`.
3. Run real 2-user E2E (`runMatchingGameRoundNow` + devices).
4. Observe one live Istanbul hour tick (or admin-triggered equivalent with logging).

## Safe to ship to stores?

**No.** Shipping Flutter with `hourlyGlobalMatchingGame = true` while callables are missing disables the old dwell path and leaves Discover without a working personality-game backend.
