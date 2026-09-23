# Mevora Humor Lab

Isolated Reels-style humor discovery. Users watch vertical video/image content,
rate “how funny?”, and build a **UserHumorProfile**.

## Product entry

- **Discover** promo card (`HumorLabDiscoverEntry`) when `humorLabEnabled`
- **Profile** tile (same flag)
- Route: `/humor-lab` overlay — **not** a 5th tab, **not** under Settings

## Content pipeline

```text
Giphy (licensed API, lang=tr) ──┐
Internal Turkish media seed ────┼─► validate → moderate → tag → humorContent
                                │
Flutter vertical feed ◄── getHumorFeed ◄── Firestore
        │
 submitHumorFeedback → users/{uid}/humorInteractions + humor/summary
```

**No** Instagram / TikTok / YouTube scraping.

### Provider

- Adapter: `functions/src/humor/sourceAdapter.ts` + `giphySource.ts`
- Config: `GIPHY_API_KEY` via `firebase functions:secrets:set GIPHY_API_KEY`
- Admin sync: `syncHumorFromProvider` (requires admin claim + key)
- Without key: Turkish-first **internal seed** with real HTTPS MP4/images still works

### Feed language

Default preference: `tr` then `en`. App language TR → Turkish content first.

## Initial calibration

The first **15** rated interactions are a structured calibration milestone,
served instead of the personalized feed:

| Stage | Interactions | Purpose |
|---|---|---|
| **Anchor** | 1–6 | Comparable baseline across users, one curated *anchor slot* each |
| **Adaptive** | 7–12 | Separate a strong signal from its nearest neighbours |
| **Exploration** | 13–15 | Highest information gain — undercovered / weakly evidenced dims |

Server-owned state lives at `users/{uid}/humor/calibration` (`calibrationVersion = 1`).
It sits inside the existing `users/{uid}/humor` collection on purpose, so the
owner-read/client-write-denied rule and the account-deletion sweep both cover it
without new rules.

### Not everyone sees the same memes

An anchor slot is a *measurement role*, not a content id. Multiple curated items
may fill the same slot; `calibrationFeed.ts` rotates between them with a
deterministic FNV-1a seed of `uid + version + slot`. Same user ⇒ same item (so an
interrupted calibration resumes onto it); different users ⇒ different items. No
`Math.random`, so the selection stays unit-testable.

### Curation is opt-in

`humorContent` carries three flat fields — `calibrationEligible`,
`calibrationSlot`, `calibrationVersion`. All default closed, so bulk-ingested
Giphy content can never drift into an anchor pool. Only an explicit admin
`upsertHumorContent` call or the curated internal seed opts an item in; an
unknown slot id is rejected outright.

If a pool is short, calibration degrades gracefully: positions are filled from
ordinary feed content, the gap is reported as `insufficientPool`, and the state
records a `degradedCount`. Uncurated content **never** claims an anchor slot.

### Calibration ≠ end of learning

Completing the 15 does not freeze anything. `submitHumorFeedback` keeps updating
the humor vector, `interactionCount`, `confidence` and explored categories
indefinitely. `profileBuilding` now means "initial calibration still running",
not "the profile stopped learning".

## Feature flag

`FeatureFlags.humorLabEnabled` (product default false). Debug+dev ON via `resolveHumorLabEnabled`.

## Flutter media

- `video_player` for MP4 autoplay / mute / loop / pause when off-screen
- Images/memes via `MevoraNetworkImages`
- Vertical `PageView` + 5-level rating bar + undo

## Setup

```bash
# Optional production Giphy
firebase functions:secrets:set GIPHY_API_KEY

# Seed internal catalog (admin callable)
# seedInternalHumorContent

# Sync licensed GIFs (admin)
# syncHumorFromProvider { language: "tr", limit: 24 }
```

Client mock (default `USE_MOCK_HUMOR=true`) uses the same Turkish media URLs for local QA.
Pass `--dart-define=USE_MOCK_HUMOR=false` to hit Cloud Functions.

## Compatibility

MVP does **not** change `calculateCompatibility` / Discover ranking.
