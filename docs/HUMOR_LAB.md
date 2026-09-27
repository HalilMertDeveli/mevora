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

### Seed media credits

The curated seed's video items reuse four short, openly licensed H.264 MP4
clips (`SEED_VIDEO_CLIPS` in `calibrationSeed.ts`). Each clip is 5–10 s long
and about 1 MB. The humour is in each item's Mevora-written caption. The clips
have no poster on an allowed host, so their `thumbUrl` is `null` and the
player shows a black frame while the clip loads.

| Clip | Source | Licence / credit |
|---|---|---|
| Big Buck Bunny, 10 s, 360p | test-videos.co.uk | CC BY 3.0, © 2008 Blender Foundation, peach.blender.org |
| Sintel, 10 s, 360p | test-videos.co.uk | CC BY 3.0, © Blender Foundation, durian.blender.org |
| `flower.mp4`, 5 s | MDN interactive examples, `media/cc0-videos/` | CC0 1.0 |
| `friday.mp4`, 6 s (*His Girl Friday*, 1940) | MDN interactive examples, `media/cc0-videos/` | CC0 1.0 |

Stills come from `picsum.photos`. The Google `gtv-videos-bucket` samples used
before now return 403, and their host was removed from the media allowlist.
Before you change a clip, check it with a live GET: it must return 200/206 with
`video/mp4`.

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
   items, four candidates per anchor slot). Re-seeding is idempotent and never
   resets anyone's calibration progress.
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
node tool/humorCalibrationQa.cjs --emulator     # optional end-to-end calibration check
```

Or run the whole sequence without the app:
`powershell -NoProfile -ExecutionPolicy Bypass -File tool/ensure_emulators.ps1`.
The calibration check creates and removes scratch users, but its ratings stay
in the catalogue's `stats`.
