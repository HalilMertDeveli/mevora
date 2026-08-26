# Discover Fallback — Implementation Report

**Date:** 2026-08-23  
**Goal:** Reduce empty Discover decks without rewriting the matching / compatibility engine.

## Behavior

```text
Nearby (within preferred radius / boost-extended)
        ↓ fill if needed
Extended (up to 100 km)
        ↓
Far (up to 500 km)
        ↓
No location (viewer or candidate)
        ↓
Client radius ladder 5→10→25→50→100 with soft expand
        ↓
Empty state only if still nothing
```

**Never relaxed:** self, blocked, liked, passed, matches, banned/ineligible, under-18, inactive (>90d), smoke isolation.

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
