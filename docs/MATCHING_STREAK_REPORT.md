# Matching Streak System — Final Report

Branch: `feature/matching-streak`  
Base: `c2a4335` (hourly global personality / Match Game)  
Date: 2026-08-27

## Goal

Encourage daily continuity: users who join at least one Mevora Hour / Match Game on an **Europe/Istanbul** calendar day earn **at most +1** streak that day. Rewards are configurable. Streak is **backend-owned** (clients cannot write).

## Non-goals / preserved systems

- Existing discovery matching, personality questions, and Premium flows are unchanged.
- Hourly Match Game rules/engine untouched except a participation hook on join.
- Rewards catalog is data/config — not hard-coded grant branches in the engine.

## Architecture

### Participation hook

`joinMatchingGameRound` (Cloud Function) calls `recordMatchingGameParticipation(uid, roundId)` on:

- first join of a round
- rejoin (already joined) — still idempotent for the Istanbul day

Same-day 10 games → still streak **1**.

### Timezone

- Canonical day key: `YYYY-MM-DD` in **Europe/Istanbul** (not UTC midnight).
- Turkey is permanently UTC+3; client policy mirrors this for display when Firestore has not yet rolled over.

### Firestore (Admin write only)

| Path | Purpose |
|------|---------|
| `users/{uid}/matchingStreak/current` | streak counters, last day, unlocked reward ids |
| `users/{uid}/matchingStreakDays/{YYYY-MM-DD}` | day participation audit |
| `users/{uid}/matchingStreakRewards/{rewardId}` | unlocked reward records |

Rules: owner **read**, client **write denied**.

### Backend modules

- `matchingStreakEngine.ts` — pure rules (`applyParticipation`, `effectiveStreak`, `dailyParticipation`, Istanbul day helpers)
- `matchingStreakConfig.ts` — `MATCHING_STREAK_REWARDS` + reminder hour
- `matchingStreak.ts` — transaction write, `getMatchingStreak` callable, `matchingStreakReminderTick` schedule (`0 20 * * *` Istanbul)

### Default configurable rewards

| Days | Id | Type |
|------|----|------|
| 7 | `streak_7_profile_badge` | `profile_badge` |
| 14 | `streak_14_compatibility_insight` | `compatibility_insight` |
| 30 | `streak_30_boost_discount` | `boost_discount` (payload `percentOff: 20`) |

Future rewards (e.g. Premium trial) = add an entry to the config array.

### Notifications

- FCM type `streakReminder`
- Pref key `streakNotifications` (default **on** when unset)
- Settings UI toggle; uses existing `sendUserPush` preference gate
- Copy (TR): “🔥 Streak'ini korumayı unutma.”

### Client

- Feature module `lib/features/matching_streak/`
- Profile tile: 🔥 N Day Streak + keep / kept-today copy
- DI: `MatchingStreakScope` + bootstrap wiring
- Reads Firestore; optional refresh via `getMatchingStreak`

### Account deletion

`deleteUserAccount` also deletes `matchingStreak`, `matchingStreakDays`, `matchingStreakRewards`.

## Streak rules (examples)

| Scenario | Result |
|----------|--------|
| First day join | streak **1**, `dailyParticipation=true` |
| Same day join again | no increment |
| Next Istanbul day join | streak **+1** |
| Miss a full Istanbul day | effective streak **0**; next join → **1** (longest retained) |
| UTC late evening / Istanbul next morning | counted on Istanbul day |

## Persistence across sessions

Streak is keyed by **Firebase UID** in Firestore:

- Logout / login → same streak
- Device change → same streak
- Account deletion → streak data removed

## Tests

### Backend (`functions/test/matchingStreakEngine.test.cjs`)

- First day, same-day idempotency, next day, miss day, Istanbul vs UTC day, month boundary, reward unlock once, 10 games same day

### Client (`test/features/matching_streak/matching_streak_policy_test.dart`)

- Istanbul day key, dailyParticipation, effectiveStreak, previous day

## Security summary

- No client writes to streak docs (rules deny)
- Only Cloud Functions Admin SDK mutates streak
- Reminder respects notification prefs

## Deploy notes (not done in this branch)

1. Deploy functions: `getMatchingStreak`, `matchingStreakReminderTick`, updated `joinMatchingGameRound`, `notifications`
2. Deploy `firestore.rules`
3. Collection group query on `matchingStreak` may need a composite index (`currentStreak`) — create if console prompts

**Note:** Full `functions` `tsc` on this base (`c2a4335`) already references missing `functions/src/automation/*` modules. Streak engine unit tests were compiled/run in isolation and pass (9/9). Flutter analyze on streak-touched paths: clean. Client policy tests: 4/4 pass.

## Git

Work isolated on `feature/matching-streak` (worktree `D:\Mevora-matching-streak`). **No merge** performed.
