# Hourly Global Matching Game

## What changed

Replaced Discovery **3-minute dwell** personality offers with an
**hourly Europe/Istanbul matching game**. Existing relationship questions
and answer options are **unchanged**.

## Round lifecycle

1. Scheduler `matchingGameHourlyTick` runs `0 * * * *` with
   `timeZone: Europe/Istanbul`.
2. Creates `matchingGameRounds/{YYYYMMDDHH}` (`OPEN`) idempotently.
3. Locks + matches the **previous** hour round (`optimizeMatches`).
4. Clients call `getMatchingGameRound` / `joinMatchingGameRound` /
   `submitMatchingGameAnswers` / `getMatchingGameResult`.

## Scoring

Answers remain `a|b|c`. Ordinal distance:

`similarity = 1 - |ord(a)-ord(b)| / 2`

Session score = average similarity × 100.

Ranking: exact aligned → avg distance → score → uid tie-break.
Matching: top-K edges + greedy 1:1 (deterministic).

## Flutter

`RelationshipQuestionConfig.hourlyGlobalMatchingGame = true` disables the
dwell timer and opens offers from the current Istanbul round for all
eligible completed profiles (not only zero-chat users).
