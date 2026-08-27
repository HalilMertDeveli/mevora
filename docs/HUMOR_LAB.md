# Mevora Humor Lab

Isolated product surface that learns what makes a user laugh and builds a
**UserHumorProfile** over time. MVP is intentionally **not** wired into
Discover ranking, overall Compatibility Engine weights, Relationship Questions,
Spotify, or E2EE messaging.

## Architecture

```text
Internal humorContent catalog
        ↓
getHumorFeed (personalized + exploration)
        ↓
Humor Lab vertical feed (Flutter)
        ↓
submitHumorFeedback (5-level rating)
        ↓
users/{uid}/humor/summary  (CF-only write)
```

AI may tag **content** (category / tags / vector / safety) only.
User ratings are the sole humor-model signal. Runtime feed does not call AI.

## Feature flag

- Client: `FeatureFlags.humorLabEnabled` (default **`false`**)
- Remote Config key: `humorLabEnabled`
- When off: `/humor-lab` redirects to Discover, Profile tile hidden, no Humor UI

Rollback = set flag false. Data may remain; no need to delete.

## Firestore

| Path | Client |
|------|--------|
| `humorContent/{contentId}` | Read approved+active only; write CF/Admin |
| `users/{uid}/humor/summary` | Owner read; write CF only |
| `users/{uid}/humorInteractions/{contentId}` | Owner read; write CF only |
| `humorReports/{id}` | Reporter/admin read; write CF |
| `humorModerationQueue/{id}` | Admin read; write CF |

Peers never read raw humor vectors. Pair scores are computed on demand.

## Cloud Functions (`europe-west1`)

| Callable | Role |
|----------|------|
| `getHumorFeed` | Paginated personalized feed |
| `submitHumorFeedback` | Rating → EMA profile update |
| `getHumorProfile` | Own profile (basic / detailed) |
| `getMatchHumorCompatibility` | Standalone pair score (MVP unused by Discover) |
| `reportHumorContent` | User report → moderation queue |
| `upsertHumorContent` | Admin CMS upsert |
| `runHumorModeration` | Admin safety decision |
| `seedInternalHumorContent` | Admin internal seed (no scraping) |

Source: `functions/src/humor/`.

## Flutter

- Feature module: `lib/features/humor/`
- DI: `HumorScope` + `createHumorServices` (mock by default via `USE_MOCK_HUMOR=true`)
- Route: `/humor-lab` (overlay; **no** 5th tab)
- Entry: Profile tile when flag enabled

## Scoring

Rating weights: very_funny +1.0, funny +0.6, neutral 0, not_funny −0.5, not_at_all −1.0.

EMA updates profile dims to **0..100**. Confidence grows with interaction count.
UI “building” state until ~15 interactions.

Feed ranking: 0.55 affinity + 0.15 novelty + 0.15 exploration + 0.10 quality + 0.05 language,
with ~18% exploration slots.

Pair formula (standalone / V2): 0.70 cosine + 0.20 topK overlap + 0.10 (1 − divergence).

## Moderation

Zero-tolerance auto-reject: `minorRelated`, `illegal`, `extreme`.
Borderline (nsfw/hate/harassment/violent/sexual) → `needs_review`.
Only `active && safetyStatus==approved` is served.

## Privacy

- Interactions & summary: owner + CF only
- Account delete clears `users/{uid}/humor` and `humorInteractions`
- Analytics: metadata only (contentId, rating, category) — no PII / message text

## Analytics

`humor_lab_opened`, `humor_content_viewed`, `humor_content_rated`,
`humor_content_skipped`, `humor_content_replayed`, `humor_content_saved`,
`humor_profile_viewed`, `humor_compatibility_viewed`,
`humor_chat_starter_shown`, `humor_chat_starter_used`

## Compatibility regression

With `humorLabEnabled = false`, `calculateCompatibility` is unchanged
(no `humorScore` field). Covered by `functions/test/humorLab.test.cjs`.

## MVP / V2 / V3

| Phase | Scope |
|-------|--------|
| **MVP** | Feed → rating → profile; flag off by default; isolated |
| **V2** | Match humor badge/sheet, Why You Match reason, chat starter chip, premium detailed profile |
| **V3** | Optional overall weight ~0.10 with renormalize; Discover soft ranking |

## Testing

```bash
cd functions && npm test   # includes humorLab + compatibility baseline
flutter analyze
flutter test
```

## Rollback

1. `humorLabEnabled = false`
2. Confirm Discover / Matching / Music / Chat unchanged
3. Callables may remain deployed; clients stop calling them
