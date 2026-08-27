# Profile Quality Score

## Purpose

`ProfileQualityScore` (0–100) is a **ranking + UX signal**. It never hard-excludes users from Discover and never blocks Boost purchase. Onboarding required fields are unchanged.

## Inputs (real profile data)

| Factor | Weight | Notes |
|---|---:|---|
| Photos (3+) | 25 | Rejected photos ignored; pending/approved with assets count |
| Bio | 12 | ≥ 8 trimmed characters |
| Age / birth date | 8 | Present on profile |
| Location | 10 | City label **or** lat/lng |
| Relationship goal | 10 | Non-empty string |
| Personality / Q&A | 20 | Relationship answer count toward 3 |
| Profile completed flag | 10 | `profileCompleted` |
| Recent activity | 5 | From `users/{uid}.lastActiveAt` |
| Spotify | **+5 bonus** | Optional only — missing Spotify never lowers baseline targets |

Core weights sum to **100 without Spotify**. Spotify can push raw slightly over 100; score is clamped to 100.

## Floor

`PROFILE_QUALITY_FLOOR = 15` so sparse / legacy profiles are not scored to zero and remain visible in ranking blends.

## Backend

| Piece | Path |
|---|---|
| Pure scorer | `functions/src/recommendation/profileQuality.ts` |
| Callable | `getProfileQualityScore` |
| Discover attach | `profileQualityScore` on discovery cards (`backend.ts`) |
| Soft rank lift | +0–4 in `computeDiscoveryRankScore` (`boost/ranking.ts`) |

### Personality count on Discover

Discover batch-loads `users/{uid}/relationshipMatch/summary` per candidate page (`loadPersonalityAnswerCounts`) and uses `personalityAnswerCountFromSummary` (max of validated `answers` keys and stored `answerCount`). That count is combined with `profile.relationshipAnswerCount` via `Math.max`, so missing profile fields no longer under-weight personality.

The owner callable still also considers `relationshipAnswers` collection size when higher than the summary.

## Flutter

| Piece | Path |
|---|---|
| Calculator | `lib/features/profile/domain/services/profile_quality_calculator.dart` |
| Profile / edit UI | `ProfileQualitySection` → “Profile Quality N%” + missing list |
| Boost | Soft tip only via `ProfileQualityBoostHint` (purchase stays enabled) |

## Constraints (unchanged)

- Spotify remains optional bonus-only.
- Floor stays at 15.
- Never blocks Boost purchase.
- Never hard-excludes Discover candidates.

## Remaining follow-ups

- `UserProfile.lastActiveAt` is not always hydrated from Firestore on the client; activity factor often uses the gentle “unknown” partial credit.
- Smart Boost preview UI is not on this branch; soft tip is on the classic Boost screen.
- Optional Spotify tip is intentionally **not** in the missing-items list.
