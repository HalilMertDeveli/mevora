# Mevora Humor Lab

Isolated Reels-style humor discovery. Users watch vertical video/image content,
rate “how funny?”, and build a **UserHumorProfile**.

## Product entry

- **Discover** promo card (`HumorLabDiscoverEntry`) when `humorLabEnabled`
- **Profile** tile (same flag)
- Route: `/humor-lab` overlay — **not** a 5th tab, **not** under Settings

## Content pipeline

```text
Giphy (licensed API, lang=tr) ─► map → relevance filter → dedup ─┐
Curated Mevora text jokes ───────────────────────────────────────┼─► validate → moderate → tag → humorContent
                                                                 │
Flutter vertical feed ◄── getHumorFeed ◄── Firestore
        │
 submitHumorFeedback → users/{uid}/humorInteractions + humor/summary
```

**No** Instagram / TikTok / YouTube scraping, and no server-side media download.

### Content policy: one coherent item per card

Every card is one thing whose parts were made for each other. We never attach
our own text to someone else's media, and never put a picture behind a joke
that was not made for it.

- **Curated (Mevora-authored)**: text-only joke cards — `type: "text"`,
  `media.textBody` = the joke, `downloadUrl` / `thumbUrl` = `null`,
  `attribution: null`, `sourceTrust: "curated"`. The calibration catalogue in
  `calibrationSeed.ts` is exactly this. (It used to glue captions onto random
  picsum stills and four stock clips — a grocery joke over a seascape, a fridge
  joke under a sword fight. That is gone, and so are those hosts.)
- **Provider (GIPHY)**: the item's own animated image (a Clip: its own MP4),
  its own still frame as poster, and its own title as caption (cleaned of "GIF", "GIF by …", "by <user>"). An empty,
  generic or uploader-only title becomes `textBody: null` — never invented text.
  Credit is stored as `attribution` and sent to the client (contract K1).

Re-seeding is safe on old data: `upsertHumorContentDoc` writes every media key
explicitly (null when unset) and forces a text card's media to null, so a merge
over a document that still carries old stock media clears it.

Media host allowlist (`contentValidation.ts`): `giphy.com` (suffix match covers
`media*.giphy.com`, `i.giphy.com`) and `firebasestorage.googleapis.com`. HTTPS
only; posters are checked like media.

### Provider

- Adapter: `functions/src/humor/sourceAdapter.ts` + `giphySource.ts`;
  relevance: `providerRelevance.ts`; pipeline: `ingest.ts`
- Config: `GIPHY_API_KEY` via `firebase functions:secrets:set GIPHY_API_KEY`
  (emulator: `functions/.secret.local`, added by the owner)
- Admin sync: `syncHumorFromProvider { language, limit, clips? }` (admin claim + key)
- Without key: the curated text catalogue still works; nothing else changes

**Queries.** Intentional families, Turkish first — `komik tepki`, `komik sahne`,
`dizi komik`, `film komik`, `komedi`, `kahkaha`, `şaşkınlık`, `sarkazm`, `ironi`,
`türk meme`, `sitcom` — then English fallback (`funny reaction`, `comedy
reaction`, `sitcom reaction`, `funny tv`, `comedy scene`, `movie reaction`,
`sarcastic reaction`, `awkward reaction`, `absurd comedy`, `dry humor`,
`laughing reaction`). Each family carries the humor category it probes, which is
the primary category signal (weight ≤ 0.6; a keyword in the item's own text adds
a secondary dimension at 0.35). Rotation is deterministic: the UTC day number
picks the starting family and page.

**Renditions.** A GIF is a silent short loop — an image, not a video — so it is
stored as `type: "meme"` with an animated image the client shows through
Flutter's own image pipeline (which decodes and loops animated WebP/GIF):
`original.webp` when `webp_size` ≤ 1.5 MB, else `downsized_medium` (animated
GIF), else the wider of `fixed_width.webp` / `fixed_height.webp`, else the
smallest known WebP; `aspectRatio` comes from the chosen rendition. Only a GIF
with no animated-image rendition falls back to its MP4 (the highest-resolution
one ≤ 2.5 MB among `original_mp4`, `fixed_height.mp4`, `downsized_small.mp4`)
as `type: "video"`. Why: on an Android 16 emulator (media3 1.9.2) ExoPlayer
often never received a byte for GIPHY's small MP4s — 12 s init timeouts, two
attempts, "Video yüklenemedi" — while the posters from the same CDN loaded at
once through the image stack. Clips (`/v1/clips/search`, needs GIPHY approval;
opt in with `clips: true` or `GIPHY_CLIPS_ENABLED=true`) are real video with
sound and stay MP4 `video`: `480p`, else `360p`, else `720p`, never 1080p/4k;
401/403/404 fall back to GIF search silently. Poster: `fixed_height_still`,
else `original_still`. Docs ingested earlier as GIF MP4 video are switched by
the sync when the same GIF is fetched again — `type` and
`media.downloadUrl`/`aspectRatio` only, and only while the doc is approved and
active; rejected or inactive docs and Clips are never touched. (Restarting the
emulator wipes its data, which also re-ingests with the new rendition.)

**Relevance (deterministic, no LLM).** Accept only items whose title / slug /
alt text / tags carry a TR+EN humour, reaction or comedy marker, or that come
from a verified entertainment account through a comedy query. Reject the
stop-list (wallpaper, landscape, nature, background, scenery, loop pattern,
abstract, aesthetic, logos, greeting cards such as "happy birthday" /
"günaydın", transparent stickers), any rating other than g / pg / pg-13, and
items without usable HTTPS media. Fewer items beat filler.

**Trust tiers** (`sourceTrust` on the doc): `curated`, `verified_provider`
(GIPHY `is_verified` or a known studio/network account), `provider`,
`qa_fixture`. Verified content gets +0.08 on the humor feed's 0.55 quality prior
(at most +0.008 on the total score; real ratings replace the prior by 20
ratings). Discover ranking and the compatibility engine do not read it.

**Dedup.** Stable id `ext_giphy_<sourceId>`; within a batch also by media URL and
by normalized title + uploader. An existing document is never rewritten.
Provider content is never calibration-eligible.

**Diagnostics.** `syncHumorFromProvider` returns `{requested, fetched, accepted,
rejected: {reason: n}, duplicates, errors, clipsAvailable}` and logs one
counts-only line (never the key or a URL).

### Feed and feedback contracts

- **K1** — every feed card carries `attribution: {provider, displayName,
  username, sourceUrl, verified} | null` (null for curated content).
  `media.thumbUrl` stays the poster.
- **K3** — `submitHumorFeedback` accepts `skipReason: "user" | "media_failed"`
  only with `skipped: true` (anything else becomes `"user"`), stored on the skip
  marker. A skip still never counts toward calibration or the profile.

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

### Calibration content system

Curation lives in `functions/src/humor/calibrationSeed.ts`, separate from
persistence. Each of the six anchor slots carries **four** interchangeable
candidates, so two users calibrated on the same slot rarely see the same asset.

Every anchor candidate must measure its slot's `primary` dimension; a test
enforces it. A candidate is *not* required to measure the slot's `contrast` —
an item scoring high on both sarcasm and dry cannot separate them. The contrast
is what the adaptive stage probes afterwards.

**Guaranteed anchor coverage is the six slot primaries**: absurd, cringe, meme,
sarcasm, situational, wordplay. That is the intersection across every rotation,
which is what makes two profiles comparable. Deeper pools deliberately traded
incidental secondary overlap for content variety. The remaining five dimensions
— dry, silly, teasing, romantic, dark — are reached by the adaptive and
exploration stages, and a test proves they are not stranded.

The seed is the **QA / development tier**, marked `provider: mevora-qa-seed`.
Production curation is content-ops work; the architecture is what makes it
possible without code changes.

`getHumorCalibrationPoolReport` (admin callable) reports per-slot candidate
counts, guaranteed coverage, uncovered dimensions and warnings. Calibration
degrades quietly when a pool runs thin, so this is how a catalog gap becomes
visible before users hit it.

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

## Daily set — "Bugünün Mizah Turu"

After calibration, every eligible member gets the same ten moving items
(videos, or provider GIFs shown as animated images) per canonical day, in the
same order. Code: `functions/src/humor/daily.ts` (pure rules) and
`dailyService.ts` (Firestore); callables `getDailyHumorSet`,
`submitDailyHumorResponse`, admin `publishDailyHumorSet` /
`repairDailyHumorSlot`.

- **Canonical day**: one global day turning over at midnight Europe/Istanbul
  (UTC+3, no DST) — the same boundary daily Picks use. The server clock picks
  it; the client sends nothing that could choose a day.
- **Manifest** `humorDailySets/{dayId}`: published once, by a transaction
  (`create` on a missing document), on the first eligible request or by the
  admin callable. Never reshuffled. Clients cannot read or write it.
- **Selection**: deterministic from the day and the pool, not personalised.
  Eligible = active, approved, moving media on an allowed https host, not a QA
  fixture, signal on its own dimension. Breadth first across the eleven
  dimensions, at most 2 per dimension, at least 5 dimensions; non-anchor items
  preferred; items of the previous 2 published days kept out (relaxed a day at
  a time only if the pool cannot otherwise fill a valid set). A day the pool
  cannot fill is recorded `not_ready` and re-checked at most every 15 min —
  never padded.
- **Pacing**: first set the day after calibration completes
  (`starts_tomorrow` until then); uncalibrated members are locked
  (`calibration_incomplete`); existing calibrated members and legacy ready
  profiles are eligible without redoing calibration. Missed days are missed —
  no backlog.
- **Answers** `users/{uid}/humorDaily/{dayId}` (owner-read, server-write):
  each rating runs through the Humor Lab feedback transaction
  (`applyHumorFeedbackInTx`) inside the same transaction as the progress
  write, so the lifetime profile learns at most once per item, a changed
  rating replaces the earlier contribution, and double taps are no-ops. The
  only skip is `media_failed` (fills the slot, teaches nothing, never
  overrides a rating). The last available slot completes the day.
- **Taken-down items**: a published item that stops being servable drops out
  of everyone's day (the day shrinks) — replacing it is an explicit,
  versioned admin repair (`version` + `repairs[]`).
- **Agreement helper** `dailyResponseAgreement(a, b)`: over content ids both
  members rated only (missing ≠ neutral), `1 − |wA − wB| / 2` per item, mean
  as 0–100, `null` below 3 shared items. Standalone — Discover ranking, the
  compatibility engine and the `getMatchHumorCompatibility` payload (C5) do
  not read it.
- **Account deletion** removes `users/{uid}/humorDaily`; the global
  manifests hold no member data and stay.
- **Emulator clock**: `devClock/humorDaily {dayId}`, read only when
  `FUNCTIONS_EMULATOR=true`; rules deny every client. Drive it with
  `node tool/humorDailyDev.cjs status | publish | clock +1 | clock clear`.

## Feature flag

`FeatureFlags.humorLabEnabled` (product default false). Debug+dev ON via `resolveHumorLabEnabled`.

## Flutter media

- `video_player` for MP4 autoplay / mute / loop / pause when off-screen (Clips)
- Images/memes (GIPHY GIFs as animated WebP/GIF included) via
  `MevoraNetworkImages`: poster + spinner until the first frame, bounded by
  `imageLoadTimeout` (15 s); failure → "Tekrar dene" (once) / "Sonraki"
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

Humor always uses the real backend (`FunctionsHumorDataSource` → Cloud Functions,
or the Functions emulator with `USE_EMULATORS=true`) unless a **debug/profile
development** build passes `--dart-define=USE_MOCK_HUMOR=true`. Only that exact
opt-in selects the in-memory client mock (same Turkish media URLs, no server
state, nothing persists); staging, production and release builds ignore it
(`resolveUseMockHumor` in `lib/core/di/humor_services_factory.dart`).

## Compatibility

MVP does **not** change `calculateCompatibility` / Discover ranking.

## Local emulator QA (F5)

Cloud Billing is disabled on `mevora-d6ed0`, so every deployed callable fails.
The Firebase Emulator Suite is the working backend for Humor Lab QA.

**One click.** In VS Code, press F5 on **Mevora (development · full emulator
suite)**, the first (default) configuration. Its preLaunchTask runs
`tool/ensure_emulators.ps1`, then the usual `Flutter: Prepare Run`:

1. Rebuilds `functions/lib` when any `functions/src` file is newer, running
   `npm ci` first when `functions/node_modules` is missing.
2. Reuses a running suite, or starts
   `firebase emulators:start --config firebase.qa.json --project mevora-d6ed0 --only auth,firestore,functions,storage`
   in a minimized **Mevora Firebase Emulator Suite** window that keeps running
   after the launch (Ctrl+C there stops it). It waits up to 180 s for the hub
   to report all four emulators and for the functions to load.
3. Seeds the QA users `qa_user_a…d@mevora.test` (only missing ones, so
   existing matches and chats survive) and the curated humor catalogue (36
   text joke cards, four candidates per anchor slot). Re-seeding is idempotent,
   never resets anyone's calibration progress, and converts documents an older
   seed left with stock media into text cards. Then the provider top-up: when
   `functions/.secret.local` declares `GIPHY_API_KEY` (the script checks the
   name only), it calls `syncHumorFromProvider` on the Functions emulator as a
   throwaway emulator admin and prints the counts; otherwise it prints
   `Provider content skipped: GIPHY key unavailable (billing disabled; add
   functions/.secret.local to enable)`. A provider failure never fails F5.
4. Prints `ensure_emulators: READY | …`, or fails with the reason and VS Code
   does not launch the app.

Nothing targets the cloud: nothing is deployed, and the seed scripts refuse to
run unless `FIRESTORE_EMULATOR_HOST` is a loopback address. A suite already
running from another worktree is reused, with a warning that its callables run
that worktree's functions code.

**Fresh AVD.** Android 16+ needs `ACCESS_LOCAL_NETWORK` to reach `10.0.2.2`,
and `Flutter: Prepare Run` can only grant it to an app that is already
installed, so the very first launch cannot reach the emulators. After that
install, run
`adb shell pm grant com.mevora.app android.permission.ACCESS_LOCAL_NETWORK`
and restart the app; every later F5 grants it automatically.

**Manual fallback** (PowerShell, repo root):

```powershell
npm --prefix functions run build
firebase emulators:start --config firebase.qa.json --project mevora-d6ed0 --only auth,firestore,functions,storage

# in a second terminal
$env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
$env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"
node tool/seedEmulatorQaUsers.cjs --if-missing  # without the flag: resets every QA user
node tool/seedEmulatorHumorCatalog.cjs          # catalogue + anchor-slot pool report
# optional licensed top-up (needs functions/.secret.local with GIPHY_API_KEY):
node tool/seedEmulatorHumorCatalog.cjs --provider-topup --functions-host 127.0.0.1:5001
node tool/humorCalibrationQa.cjs --emulator     # optional end-to-end calibration check
```

Or run the whole sequence without the app:
`powershell -NoProfile -ExecutionPolicy Bypass -File tool/ensure_emulators.ps1`.
The calibration check creates and removes scratch users, but its ratings stay
in the catalogue's `stats`.
