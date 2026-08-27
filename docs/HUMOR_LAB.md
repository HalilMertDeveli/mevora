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
