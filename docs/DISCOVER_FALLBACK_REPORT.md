# Discover Fallback — Implementation Report

**Date:** 2026-08-23  
**Goal:** Reduce empty Discover decks without rewriting the matching / compatibility engine.

## Behavior

```text
HARD GATE: exact haversine > min(radiusKm, 100 km)  →  candidate dropped
        ↓ (everyone below is already inside the gate)
Nearby (within preferred radius / boost-extended)
        ↓ fill if needed
Extended
        ↓
Far
        ↓
No location (viewer or candidate)
        ↓
Client radius ladder 5→10→25→50→100 with soft expand
        ↓
Empty state only if still nothing
```

**Never relaxed:** self, blocked, liked, passed, matches, banned/ineligible,
under-18, inactive (>90d), smoke isolation, **and distance beyond the
resolved radius**.

### Update 2026-09-27 — distance became a hard gate

Until this change distance never excluded anyone. The tiers above were the
whole story: `classifyDiscoveryDistance` had no rejecting branch, so a
candidate 12,300 km away was tagged `far` and `fillFromDistanceTiers`
served them as soon as the nearby bucket was short of `limit`. A runtime
probe confirmed it — Istanbul viewer, Buenos Aires candidate, returned as
`distanceKm: 100` / "100+ km away", and a mutual like created a real match.

`getDiscoveryCandidates` now drops a candidate whose **exact** haversine
distance exceeds `min(radiusKm, DISCOVERY_MAX_RADIUS_KM)`, counted as
`distance_over_radius` in `rejectionReasons` and echoed as `gateKm` in the
`discovery_fallback` log and the `includeDebug` payload.

Three things to know before touching this:

- The gate reads the exact haversine, deliberately **before** the disclosure
  step quantises it. `coarseDistanceKm` floors into 5 km bands and flattens
  everything at or beyond 100 km to exactly 100, so a gate fed the disclosed
  figure would admit the far side of the planet while every log line looked
  correct.
- The gate is **not** disabled under the Functions emulator.
  `relationshipMatch.ts` disables its own 100 km rule whenever
  `FUNCTIONS_EMULATOR` is set, which hides that gate from the only QA that
  would catch a regression. Discovery does not copy that.
- The gate is boost-independent. `effectiveRadiusKm` still widens the
  *nearby tier boundary* for a boosted candidate, so Boost keeps its
  ordering advantage, but it can no longer pull someone past the radius the
  viewer asked for.

Still true after this change, and worth fixing separately: the candidate
pool is selected by `updatedAt desc` over at most 3-4 pages of 40 profiles,
not by proximity, so a genuinely nearby user outside that recency window is
never considered. `userPreferences.maxDistance` remains write-only dead
state, and the disclosed distance is still banded at 5 km.

## Files touched

### Server
| File | Change |
|------|--------|
| `functions/src/discoveryFallback.ts` | **New** — distance tiers + fill helper |
| `functions/src/backend.ts` | Tiered candidate fill, batch location load, multi-page scan, `expandDistance`, `fallbackLevel` |
| `functions/src/boost/ranking.ts` | No-location distance contribution `-2` (after known-distance) |
| `functions/test/discoveryFallback.test.cjs` | Unit tests |
| `functions/package.json` | Include new test |

### Client
| File | Change |
|------|--------|
| `lib/features/discovery/domain/services/discovery_fallback.dart` | **New** — Dart mirror of tiers |
| `lib/features/discovery/domain/services/discovery_candidate_filter.dart` | Soft expand mode |
| `lib/features/discovery/domain/services/discovery_boost_ranking.dart` | No-location penalty mirror |
| `lib/features/discovery/domain/repositories/discovery_repository.dart` | `expandDistance` param |
| `lib/.../discovery_repository_impl.dart` | Pass `expandDistance` to CF |
| `lib/.../mock_discovery_repository.dart` | Auto soft-expand when nearby empty |
| `lib/.../in_memory_discovery_repository.dart` | Same |
| `lib/.../hybrid_discovery_repository.dart` | Forward `expandDistance` |
| `lib/.../discovery_controller.dart` | Escalation ladder + soft client filters + `[DISCOVER]` debug logs |
| `test/features/discovery/discovery_fallback_test.dart` | Unit tests |

## What was NOT changed
- Compatibility engine / score formulas
- Swipe / match creation logic
- Block / report systems
- Security-critical exclusions

## Tests
- Flutter: `discovery_fallback_test`, boost ranking, filter, controller — **PASS**
- Functions: `discoveryFallback.test.cjs`, `boostRanking.test.cjs` — **PASS**

## Deploy note
Deploy Cloud Functions for production behavior:
`firebase deploy --only functions:getDiscoveryCandidates`
