# Mevora Humor Lab

Isolated Reels-style humor discovery. Users watch vertical video/image content,
rate “how funny?”, and build a **UserHumorProfile**.

## Product entry

- **Discover** promo card (`HumorLabDiscoverEntry`) when `humorLabEnabled`
- **Profile** tile (same flag)
- Route: `/humor-lab` overlay — **not** a 5th tab, **not** under Settings

## Content pipeline

```text
YouTube Data API (embed) ──┐
GIPHY (CDN stream) ────────┼─► validate → moderate → tag → humorContent
(Tenor: disabled) ─────────┤
Internal licensed pool ────┘
        │
Flutter vertical feed ◄── getHumorFeed ◄── Firestore (+ live top-up)
        │
 submitHumorFeedback → users/{uid}/humorInteractions + humor/summary
```

**No** Instagram / TikTok scraping. **No** copying YouTube/GIPHY bytes into Storage.

See [HUMOR_LAB_PROVIDERS.md](./HUMOR_LAB_PROVIDERS.md) for ToS, quotas, and keys.

### Providers

- `youtubeSource.ts` + `giphySource.ts` + `providerOrchestrator.ts`
- Secrets: `YOUTUBE_DATA_API_KEY`, `GIPHY_API_KEY` (server-only)
- Admin: `syncHumorFromProvider`, `seedInternalHumorContent`
- Without keys: Turkish-first **internal seed** still works

### Feed language

Default preference: `tr` then `en`.

## Feature flag

`FeatureFlags.humorLabEnabled` (product default false). Debug+dev ON via `resolveHumorLabEnabled`.

## Flutter media

- `video_player` for Giphy/internal MP4
- `youtube_player_iframe` for YouTube embeds
- Attribution chips when required
- Vertical `PageView` + 5-level rating bar + undo

## Setup

```bash
firebase functions:secrets:set YOUTUBE_DATA_API_KEY --project mevora-d6ed0
firebase functions:secrets:set GIPHY_API_KEY --project mevora-d6ed0

# Seed internal catalog (admin)
# seedInternalHumorContent

# Sync / top-up (admin)
# syncHumorFromProvider { language: "tr", limit: 24 }
```

Client mock (default `USE_MOCK_HUMOR=true`) uses Turkish media URLs for local QA.
Pass `--dart-define=USE_MOCK_HUMOR=false` to hit Cloud Functions.

## Compatibility

MVP does **not** change `calculateCompatibility` / Discover ranking.
