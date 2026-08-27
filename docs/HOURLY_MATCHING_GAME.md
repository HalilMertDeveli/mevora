# Mevora Hour + Initial Personality Test

## Product model

1. **Initial test (once):** After onboarding, the first Discover visit opens a
   one-shot personality/compatibility test immediately (`matchingEventCount == 0`).
2. **Mevora Hour (every hour):** After the initial test, offers come only from
   Europe/Istanbul hourly rounds (`matchingGameRounds/{YYYYMMDDHH}`).
3. **Legacy 3-minute Discover dwell is disabled** (`legacyDwellOffersEnabled = false`).
   Backend unavailable must **not** re-enable dwell.

Existing relationship question catalog / IDs / answers are **unchanged**.

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

- `needsInitialPersonalityTest` → immediate initial offer (no dwell).
- After `matchingEventCount >= 1` → Mevora Hour sync via `getMatchingGameRound`.
- `legacyDwellOffersEnabled = false` in production; tests may re-enable for
  legacy regression only.
- Hourly CF not-found/unavailable → “next Compatibility Hour soon” state,
  **never** 3-minute dwell.

Discover swipe and messaging continue independently.

## Cooldown note

`MATCHING_EVENT_DURATION_MS` in `relationshipMatch.ts` is a **post-dismiss /
post-complete cooldown**, not a Discover dwell trigger.
