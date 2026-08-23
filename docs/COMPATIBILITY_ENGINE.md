# Mevora Compatibility Engine

> **Who actually fits you?**

Mevora’s compatibility layer combines profile signals, relationship question answers, and music taste into a single deterministic engine. It powers discovery ranking, match explanations, and the “Someone is thinking like you” retention card.

## Architecture

```text
Viewer profile + Candidate profile
        +
Relationship answers (optional)
        +
Music summary (optional)
        ↓
MevoraCompatibilityEngine (client)
calculateCompatibility (Cloud Functions)
        ↓
CompatibilityBreakdown
        ↓
CompatibilityReasonEngine → Why You Match UI
HiddenCompatibilityFinder → Discover card
DiscoveryRankingEngine → Feed ordering tiebreak
```

## Score categories (real data only)

| Category | Source |
| --- | --- |
| Relationship | `relationshipGoal` match |
| Interests | Shared interest tags (Jaccard) |
| Lifestyle | Lifestyle tags / `lifestyleProfile` |
| Questions | Shared relationship Q&A alignment |
| Music | Spotify summary overlap |
| Communication | Question topic `communication` when aligned |
| Proximity / Activity | Distance + `lastActiveAt` (profile engine) |

**Not implemented:** separate `humor` or `personality` profile fields do not exist in Mevora today. The UI does not fabricate those scores.

## Weights

Central config:

- Client: `lib/features/compatibility/domain/config/compatibility_weights.dart`
- Server: `functions/src/compatibility/compatibilityEngine.ts` (`WEIGHTS`)

Default blend:

- Profile engine: **40%**
- Questions: **30%**
- Music: **15%** (skipped when no music data; weights renormalize)

## Question compatibility

Existing relationship question flow is unchanged:

- 3-question sessions
- `RelationshipCompatibilityCalculator` / `relationshipScoreForPair`
- High weight in overall score
- Does **not** auto-create swipe matches

## Why You Match

`CompatibilityReasonEngine` produces deterministic reasons (no AI):

- Same relationship goal
- Shared interests
- Similar lifestyle
- N aligned of M shared questions
- Music alignment

Shown on:

- Match celebration (`MevoraMatchCelebration`)
- Discover “Why?” bottom sheet

## Hidden compatibility

Shown only when **real** data matches thresholds:

- `relationshipAlignedCount >= 2`
- `relationshipCompatibilityScore >= 70`
- `compatibilityScore >= 72`

Copy example: “Someone answered 8 questions the same way you did.”

No fake users, fake likes, or fake urgency notifications.

## Discovery ranking

Server (`getDiscoveryCandidates`):

1. Hard filters (age, gender prefs, blocks, activity, photos)
2. `calculateCompatibility` per candidate
3. `sortByBoostVisibility` (boost + overall score + music bonus)

Client applies a light compatibility tiebreak without overriding server filters.

## Caching & cost control

- No per-pair Firestore documents in v1
- Scores computed on demand during discovery fetch
- `CompatibilitySessionCache` for in-session UI reuse
- No Cloud Function call per swipe

## Safety

Blocked, deleted, and ineligible users are excluded before scoring (existing discovery filters).

## Analytics events (defined)

- `compatibility_viewed`
- `why_you_match_opened`
- `hidden_compatibility_seen`
- `hidden_compatibility_clicked`
- `compatibility_match_created`

Wire through `AnalyticsProvider` where scopes expose analytics.

## Premium roadmap

`CompatibilityFeatureGate` stubs future gating (full breakdown, hidden connections, advanced filters). No payment integration in this phase.

## Future AI (not live)

Deterministic scores remain authoritative. AI may later assist with explanations, conversation starters, or date ideas — not core scoring.
