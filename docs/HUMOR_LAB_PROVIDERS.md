# Mevora Humor Lab — Content Providers

Last reviewed: 2026-08-27

## Verdict

**Humor Lab şu anda gerçek ücretsiz içerik API'lerinden içerik alıp kullanıcıya gösterebiliyor mu?**

→ **HAYIR** (API anahtarları henüz Secret Manager / env'de yok).

Kod ve fallback hazır. Anahtarlar set edilip Functions deploy edildikten + `seedInternalHumorContent` / canlı top-up çalıştıktan sonra **EVET** olabilir.

İçerik havuzu (internal seed) gerçek HTTPS MP4/image URL'leri kullanır; bu üçüncü taraf API değildir.

---

## Provider matrix

| Provider | Active? | Free? | Key? | Commercial | Display | Storage copy | Attribution |
|----------|---------|-------|------|------------|---------|--------------|-------------|
| **YouTube Data API** | Ready (off until key) | Yes (~10k units/day; `search.list` = 100 units ≈ 100 searches/day) | `YOUTUBE_DATA_API_KEY` | Yes with ToS | **Embed/stream only** (IFrame / player) | **Forbidden** to download & rehost | YouTube branding / ToS |
| **GIPHY** | Ready (off until key) | Beta ~**100 req/hour** | `GIPHY_API_KEY` | Beta OK for prototyping; Production key may be negotiated/paid | Stream CDN URLs | **Do not** build independent GIF store without approval | **"Powered by GIPHY"** required |
| **Tenor** | **Disabled** | N/A | — | — | — | — | Public API **sunset 2026-06-30** |
| **Internal pool** | Architecture + seed | Free | — | Mevora-licensed only | Own URLs / Storage later | OK for **owned** media | N/A |

---

## Architecture

```
Flutter (no API keys)
  → getHumorFeed / submitHumorFeedback (Callable)
    → Firestore humorContent pool
    → if thin: topUpHumorFromProviders
         YouTube → GIPHY → (Tenor skipped) → internal
    → normalize → humorContent (CDN/embed metadata only)
```

Secrets: `functions/.env.mevora-d6ed0` (gitignored) or:

```bash
firebase functions:secrets:set YOUTUBE_DATA_API_KEY --project mevora-d6ed0
firebase functions:secrets:set GIPHY_API_KEY --project mevora-d6ed0
```

Then bind secrets on callables before production deploy (currently env-resolved so deploy works without secrets existing).

---

## How to get free keys

### YouTube Data API
1. Google Cloud Console → enable **YouTube Data API v3**
2. Create API key (restrict to YouTube Data API)
3. Free default quota ~10,000 units/day

### GIPHY
1. https://developers.giphy.com/dashboard/
2. Create app → Beta API key (~100 calls/hour)
3. Show “Powered by GIPHY” in UI (implemented)

### Tenor
Do not use — sunset.

---

## Data stored in Firebase

| Path | Purpose |
|------|---------|
| `humorContent/{id}` | Metadata + CDN/embed URLs (not third-party file copies) |
| `humorProviderCache/{id}` | Short TTL API result cache (metadata) |
| `users/{uid}/humorInteractions/{contentId}` | `rating`/`reaction`, `provider`, `category`, `timestamp` |
| `users/{uid}/humor/summary` | Humor profile vector / confidence |

---

## Fallback

1. YouTube (if key)
2. GIPHY (if key)
3. Tenor — skipped
4. Internal `humorContent` / seed

Errors (timeout, rate limit, bad key, empty, unsafe) are caught; feed still serves internal pool; app must not crash.

---

## Flutter

- Default `USE_MOCK_HUMOR=true` for local UI
- Real CF: `--dart-define=USE_MOCK_HUMOR=false`
- YouTube via `youtube_player_iframe` embed
- Giphy via streamed MP4/GIF URL + attribution chip
