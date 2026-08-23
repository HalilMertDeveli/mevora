# Compatibility Engine Audit

Date: 2026-08-23

## Root Cause

Discover cards showed **0%** due to a broken end-to-end chain, not a single UI bug:

1. **Server score lost in client parse** — `firestoreInt()` did not parse numeric strings from Cloud Functions JSON, so `compatibilityScore: "87"` became `0`.
2. **No fallback when top-level score missing** — `compatibilityBreakdown.overallScore` was ignored when `compatibilityScore` was `0`/absent.
3. **Empty viewer profile in Why You Match** — `_viewerProfile()` only passed `uid` + `displayName`, so client-side recalculation and reasons lacked interests/goals.
4. **No client resolution layer** — `DiscoveryController` displayed raw repository scores; `CompatibilityBreakdownMapper` did not run `MevoraCompatibilityEngine` with full viewer data.
5. **UI treated 0 as valid** — Profile details always rendered `0%`; discover badge hid at `<= 0` but left users with no score or misleading detail view.

## Data Flow

```
Current User (profiles/{uid})
  ↓ Cloud Function getDiscoveryCandidates
Candidate + compatibilityScore + compatibilityBreakdown
  ↓ DiscoveryRepositoryImpl._parseCandidate
DiscoveryCandidate
  ↓ DiscoveryController + CompatibilityScoreResolver (viewer profile)
Resolved score + CompatibilityDisplayStatus
  ↓ DiscoveryProfileCard / CompatibilityDiscoverBadge
UI (87% Compatible / Calculating / Unavailable)
  ↓ Tap
DiscoveryController.breakdownFor → Why You Match sheet
```

## Problems Found

| # | Problem |
|---|---------|
| 1 | String scores parsed as 0 |
| 2 | breakdown.overallScore not used as fallback |
| 3 | Viewer profile not loaded for discover |
| 4 | Duplicate/incomplete breakdown paths |
| 5 | 0% shown on profile details |
| 6 | No loading/unavailable states |

## Fixes Applied

- `firestoreInt` — parse numeric strings
- `DiscoveryRepositoryImpl._parseCompatibilityScore` — top-level + breakdown fallback
- `CompatibilityScoreResolver` — single source for score + breakdown
- `DiscoveryController` — `viewerProfileLoader`, resolve on fetch, cache breakdown
- `CompatibilityDiscoverBadge` — calculating / unavailable / ready states
- `MevoraCompatibilityEngine.fromCandidate` — use server category scores when present
- Localization: `compatCalculating`, `compatUnavailable`

## Scoring System

**Server (authoritative):** `functions/src/compatibility/compatibilityEngine.ts`  
Weights: profile 40%, questions 30%, music 15% (renormalized when signals missing).

**Client fallback:** `MevoraCompatibilityEngine` + discovery strategies (interests, goal, distance, age, lifestyle, activity).

Partial data → neutral strategy defaults (0.5), not zero overall.

## Firestore Mapping

Canonical fields on `profiles/{uid}`:

- `interests: List<String>`
- `relationshipGoal: string`
- `lifestyle` / `lifestyleProfile`

Cloud Function reads full profile doc; client receives `publicProfileProjection` + top-level compatibility fields.

## Cache

- `CompatibilitySessionCache` keyed `viewerUid::candidateUid`
- Invalidated on `onProfileUpdated()`

## Discover Integration

`DiscoveryController.loadCandidates` → `_loadViewerProfile` → `_resolveCompatibility` per candidate.

## Why You Match

`breakdownFor()` → `CompatibilityScoreResolver.breakdownFor()` with full viewer profile + `CompatibilityReasonEngine`.

## Loading State

`CompatibilityDisplayStatus.calculating` until viewer profile + resolution complete.

## Error State

`CompatibilityDisplayStatus.unavailable` when `CompatibilityDataQuality.insufficient` — never fake 0%.

## Tests

- `test/features/compatibility/compatibility_score_resolver_test.dart`
- `test/features/discovery/discovery_compatibility_parse_test.dart`
- Existing `compatibility_engine_v2_test.dart`

## Performance

Resolution runs once per candidate on fetch (not per frame). Cached breakdown for sheet taps.

## Remaining Risks

- Server CF must be deployed with `calculateCompatibility` (older deployments may omit scores).
- Viewer profile load adds one Firestore read per discover session (cached in controller).
- Lifestyle not on `DiscoveryCandidate` — client fallback uses interests/goals/distance; server categories preferred when present.
