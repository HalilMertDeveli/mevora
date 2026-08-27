# Hourly Global Matching Game

## What changed

Replaced Discovery **3-minute dwell** personality offers with an
**hourly Europe/Istanbul matching game**. Existing relationship questions
and answer options are **unchanged**.

Legacy dwell remains available for tests via
`RelationshipController(hourlyGlobalMatchingGame: false)`.

## Round lifecycle

1. Scheduler `matchingGameHourlyTick` runs `0 * * * *` with
   `timeZone: Europe/Istanbul`.
2. Creates `matchingGameRounds/{YYYYMMDDHH}` (`OPEN`) idempotently.
3. Locks + matches the **previous** hour round (`optimizeMatches`).
4. Clients call `getMatchingGameRound` / `joinMatchingGameRound` /
   `submitMatchingGameAnswers` / `getMatchingGameResult`.
5. Admin/emulator: `runMatchingGameRoundNow`.

Round statuses: `OPEN` → `COLLECTING` → `MATCHING` → `COMPLETED`.

## Scoring

Answers remain `a|b|c`. Ordinal distance:

`similarity = 1 - |ord(a)-ord(b)| / 2`

Session score = average similarity × 100.

Ranking: exact aligned → avg distance → score → uid tie-break.
Matching: top-K edges (default 20) + greedy 1:1 (deterministic).
Repeat pairs from the predecessor round get a score penalty.

## Flutter

`RelationshipQuestionConfig.hourlyGlobalMatchingGame = true` disables the
dwell timer and opens offers from the current Istanbul round for all
eligible completed profiles (not only zero-chat users).

Discover swipe and messaging continue independently.

## Production readiness (2026-08-27 QA)

**Build + deploy on `mevora-d6ed0`: PASS** (all six hourly functions live).

**End-to-end / scheduler tick / two-device: still NOT PRODUCTION READY** — see root `QA_STATUS.md` / `QA_REPORT.md`.

Client safety: if `getMatchingGameRound` returns not-found/unavailable, Flutter falls back to legacy Discovery dwell.

