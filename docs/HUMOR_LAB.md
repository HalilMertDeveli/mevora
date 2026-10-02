# Mevora Humor Lab

Members rate short humor content, “how funny?”, and build a
**UserHumorProfile**. Everyone rates the same canonical items in the same
order: fifteen as an initial calibration, then five per logical day — see
**Humor Core sequence** below.

## Product entry

- **Discover** card (`HumorLabDiscoverEntry`) when `humorLabEnabled`: the
  invitation while the calibration is open, the humor profile once it is done,
  with the "Bugünün Mizah Turu" card above it when a day is available
- **Profile** tile (same flag)
- Routes: `/humor/calibration` (invitation), `/humor-lab` (the calibration
  itself), `/humor/result` (the profile), `/humor/daily` (the daily five) —
  **not** a 5th tab, **not** under Settings

## Content pipeline

```text
Giphy (licensed API, lang=tr) ─► map → relevance filter → dedup ─┐
Curated clips (hand-picked, calibrationSeed.ts) ─────────────────┼─► validate → moderate → tag → humorContent
                                                                 │
                         curated catalogue ─► Humor Core sequence (explicit order)
                                                    │
Flutter ◄── getHumorFeed / getDailyHumorSet ◄───────┘
   │
 submitHumorFeedback / submitDailyHumorResponse
   → users/{uid}/humorInteractions + humor/summary + humor/core
```

**No** Instagram / TikTok / YouTube scraping, and no server-side media download.

### Content policy: one coherent item per card

Every card is one thing whose parts were made for each other. We never attach
our own text to someone else's media, and never put a picture behind a joke
that was not made for it.

- **Curated**: the hand-picked catalogue in `calibrationSeed.ts`
  (`CURATED_GIPHY_CATALOG`) — each entry a GIPHY item chosen by a person, with
  its own animated image, its own still, its category and humor vector, and
  the uploader's credit: `hc_gif_<giphyId>`, `sourceTrust: "curated"`. These
  are the items of the Humor Core sequence. (The text-joke cards an earlier
  seed wrote are retired — deactivated, never deleted.)
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
- Without key: the curated catalogue and the Core sequence work unchanged —
  they need no key at run time; only candidate search and sync do

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
- **K3** — `submitHumorFeedback` accepts `skipReason: "media_failed"` with
  `skipped: true`: the clip would not play. It is never a rating and never
  moves the profile. There is no "not interested" skip — a Core entry is a
  measurement; a plain skip from an older build records nothing.

## Humor Core sequence

Every member rates **one canonical sequence** of curated humor items, in the
same order: V1, V2, V3 … The same progression model as the Relationship Core
questions.

| When | What the member gets |
|---|---|
| **First run** | V1–V15 — the initial calibration |
| **Every logical day after that** | the next **5** open entries (V16–V20, then V21–V25, …) |

Two members who have each rated thirty Core items have rated the same thirty.
That is what makes their answers directly comparable.

Code: `functions/src/humor/coreSequence.ts` (the order), `coreSchedule.ts`
(pure rules), `coreService.ts` (Firestore), `dailyService.ts` (the daily
callables' input and output shapes).

### Rules

- **Same order for everyone.** Nothing about a member — uid, language, earlier
  answers — changes which item they get. The lifetime profile still *learns*
  adaptively from the ratings; only the content is fixed.
- **Fifteen first.** A member who stops after V7 resumes at V8, on any device.
  The calibration is complete when every one of V1–V15 is rated.
- **Five a day, and no more.** After the calibration a logical day holds at
  most `HUMOR_CORE.dailyCount` entries. When they are done the day is done;
  nothing unlocks tomorrow's.
- **The first daily five start the next day.** Finishing V15 today never opens
  V16 today — nobody rates fifteen and five in one sitting.
- **A day freezes when it is touched.** The first response of a day stores
  that day's ids on the member's state. Rating V16 therefore cannot pull V21
  into today, and a restart or a second device sees the same set.
- **Missed days do not advance.** There is no position counter and no calendar
  index: today's set is "the first open entries in canonical order". A member
  away for three days after V20 comes back to V21–V25. A day left unfinished
  carries over: two of five rated today means the other three lead tomorrow.
- **The server owns everything.** The logical day (UTC+3, Europe/Istanbul — the
  boundary Picks and the relationship questions use), the position, today's
  ids, and whether a response belongs to them are all decided server-side. The
  client sends only the content id it was shown (and, on the daily call, the
  day id it was given); both are *checked*, never trusted. An entry that is
  not in today's set — tomorrow's, an earlier one, anything that is not Core —
  is refused before anything is learned (`not-in-set`; `slot-replaced` /
  `day-closed` on the daily call).
- **Learning is unchanged.** A rating goes through the same feedback
  transaction as before (`applyHumorFeedbackInTx`): the 1–5 rating, the humor
  vector update, evidence, confidence, idempotency (same rating again is a
  no-op; a changed rating of one of *today's* entries replaces the earlier
  contribution). Fifteen ratings are a first usable profile, not perfect
  knowledge: confidence keeps growing with every daily five.

### State

`users/{uid}/humor/core` (owner-read, server-write, removed with the rest of
`users/{uid}/humor` on account deletion):

```
answers        { contentId: { rating, dayId, answeredAtMs, source: "core" | "legacy" } }
waived         { contentId: { reason: "media_failed" | "reported", dayId, atMs } }
mediaFailures  { contentId: { days[], lastAtMs } }
initialCompletedAtMs
today          { dayId, setId, contentIds[], kind: "onboarding" | "core", completedAtMs }
completedDays, migration
```

Progress is *derived* from `answers` against the sequence, so "which is the
next entry", "is the calibration done", "what is today's set", "is today done"
and "which exact entry was rated" all have one answer.

`users/{uid}/humor/calibration` stays the readiness milestone that match
compatibility, Picks, personalization and the learning journey read
(`isHumorCalibrationReady`). It still counts ratings one at a time; when the
Core calibration finishes on fewer ratings (a retired or waived entry) it is
completed in the same transaction, so a finished member is never seen as
unready. `calibrationVersion` stays `1`.

One compact record per completed day goes to `users/{uid}/humorDaily/{dayId}`
(`schema: "core-1"`). The global `humorDailySets/{dayId}` manifest is no longer
read or written.

### Identity, renditions and versions

- **The id is the joke.** A sequence entry's id is its `humorContent` document
  id and names one measurement: this clip, this joke.
- **A rendition is not a version.** Swapping the file, the CDN URL or the
  poster of the *same* clip edits the content document's `media` and keeps the
  id. The lock fixture deliberately does not record media URLs.
- **A different joke is a new entry.** A different clip, or a cut that changes
  what is funny about it, is appended as a new entry with `supersedes`, and
  the old one is retired in place. Old and new ratings never look like ratings
  of the same joke.

### Retirement and media that will not play

- **Retiring keeps the place.** A retired entry stays where it is with
  `active: false` and a `retiredReason`. Ratings of it remain meaningful; it is
  skipped for everyone who has not rated it and is **never backfilled** — a
  retired V9 makes the initial calibration fourteen items, not a different
  fifteen.
- **A take-down behaves the same.** An entry whose content document is
  rejected, deactivated or missing is skipped at serve time, so moderation can
  never dead-end a member. A day that was already frozen shrinks instead.
- **Media failure is never evidence.** When a clip will not play the client
  sends a `media_failed` skip. No rating is stored and the profile does not
  move. The entry is done for today and is offered again first thing on the
  member's next day; after it has failed on two distinct days it is waived for
  that member (still no rating, never compared). A calibration paused this way
  reports `continuesTomorrow`.
- **Nothing is ever substituted.** A broken or retired entry is not replaced
  by other content under the same position. Permanent rot is fixed by
  repairing the rendition or retiring the entry.
- **A reported entry** is waived for the reporter.

### Freeze

`functions/test/fixtures/humorCoreSequence.lock.json` records every position:
id, category and humor vector. `humorCoreSequence.test.cjs` fails when a locked
position moves, changes or disappears, and when an entry is not locked yet.

```bash
npm --prefix functions run build
node tool/lockHumorCoreSequence.cjs             # lock newly appended entries
node tool/lockHumorCoreSequence.cjs --redraft   # rewrite the lock — draft sequence only
```

**The sequence is a draft.** `HUMOR_CORE_RELEASE.released` is `false`: the 36
entries are the curated clips that were already the calibration catalogue, in
a provisional order (V1–V6 one per baseline slot, V7–V11 the other five
dimensions, so the first fifteen cover all eleven). The owner chooses the
production order. Until then `--redraft` may rewrite the lock; once `released`
is `true` the lock is append-only. A draft is handed out by the emulator only:
a deployed backend serves no Core content until the sequence is released
(`isHumorCoreServed` in `coreService.ts`) — the feed answers an empty
catalogue, the daily set stays locked and a response is refused `not-in-set`.

### GIPHY is a candidate source

Core content is curated only. `humorCoreSequenceProblems` rejects any entry
that is not a curated catalogue item, and the service serves an entry only
while its document is `sourceTrust: "curated"`, active and approved.

Provider sync (`syncHumorFromProvider`) and the curator search still exist,
but what they write (`ext_giphy_*`) is **candidate material**: it can never be
listed in the sequence, so it never reaches a member. The path to a member is

```text
provider search → preview → a person selects and tags it → curated catalogue
               → appended to the Core sequence → locked → served in canonical order
```

The scheduler takes the sequence as a parameter, so a later curator tool can
append entries from uploaded MP4s or other licensed sources without changing
the scheduling rules.

### Members from before the Core sequence

Nothing of theirs is rewritten or deleted. The first time a member touches
humor after this change their Core state is built once, lazily, from what is
already stored (`migrateLegacyHumorCoreState`); `migration` records what was
carried over.

- The lifetime profile (`humor/summary`), the interaction documents and the
  old `humorDaily/*` days stay exactly as they are.
- A real rating they already gave to a Core entry counts as that entry
  answered (`source: "legacy"`) — it is not asked again. An entry they
  reported is waived. A plain skip resolves nothing.
- A member whose old calibration was finished is **not** asked to redo
  fifteen: they take the open entries five a day, starting at V1.
- A member in the middle of the old calibration continues with what is left
  of V1–V15.
- A member who finished the old calibration today, or already did the old
  daily set today, starts tomorrow.

### What was removed

- The personalised initial fifteen (6 anchor + 6 adaptive + 3 exploration,
  rotated per uid) and its selectors.
- The global, algorithmically selected daily set of ten, its manifest, and the
  admin `publishDailyHumorSet` / `repairDailyHumorSlot` callables.
- The open-ended feed for members: once the calibration is finished
  `getHumorFeed` answers "caught up". `buildHumorFeed`'s catalogue walk is
  kept, unreferenced by any callable, for curator-side browsing.

Kept as they were: `profile.ts`, the feedback functions, `compatibility.ts`,
moderation, reports and media playback.

### Callables

| Callable | Answer |
|---|---|
| `getHumorFeed` | Calibration open: what is left of V1–V15 today. Otherwise empty, `catalogExhausted`. |
| `submitHumorFeedback` | A rating or `media_failed` skip for one of today's entries. |
| `getDailyHumorSet` | `ready` with today's entries, or `locked`: `calibration_incomplete`, `starts_tomorrow`, `sequence_complete`. |
| `submitDailyHumorResponse` | One answer in today's set. |
| `getHumorProfile` | Profile, with calibration progress from the Core state. |
| `getHumorCalibrationPoolReport` (admin) | The sequence report: every position and whether it can be served. |

The agreement helper `dailyResponseAgreement(a, b)` compares two members over
the content ids both rated (missing ≠ neutral; `coreRatedAnswers(state)` gives
the map). It is standalone: Discover ranking and the compatibility engine do
not read it.

### Admin console

`/Humor/Core` (permission `humor.read`) lists every position: V-number,
content id, active or retired, whether members can be given it, category and
top vector dimensions, provider, preview. It is read-only. There is no command
that changes the sequence — a change is a commit that passes the freeze test.

### Emulator clock and dev tool

`devClock/humorDaily {dayId}` is read only when `FUNCTIONS_EMULATOR=true`;
rules deny every client.

```powershell
$env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
$env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"      # only to pass an email
node tool/humorDailyDev.cjs status qa_user_a@mevora.test # where a member stands
node tool/humorDailyDev.cjs today qa_user_a@mevora.test  # today's entries, with V-numbers
node tool/humorDailyDev.cjs clock next --all             # one product day forward
node tool/humorDailyDev.cjs clock clear --all            # back to the real day
node tool/humorDailyDev.cjs reset qa_user_a@mevora.test --yes   # that member starts at V1 again
```

`--all` moves the relationship-questions clock too, so both features agree on
the day. `reset` deletes only that member's `humor`, `humorInteractions` and
`humorDaily` documents.

## Feature flag

`FeatureFlags.humorLabEnabled` (product default false). Debug+dev ON via `resolveHumorLabEnabled`.

## Flutter media

- `video_player` for MP4 autoplay / mute / loop / pause when off-screen (Clips)
- Images/memes (GIPHY GIFs as animated WebP/GIF included) via
  `MevoraNetworkImages`: poster + spinner until the first frame, bounded by
  `imageLoadTimeout` (15 s); failure → "Tekrar dene" (once) / "Sonraki"
- Vertical `PageView` + 5-level rating bar + undo. No skip button: the only
  way past an item without rating it is "Sonraki" on media that failed
- Every count on screen ("7 / 15", "2/5") comes from the server; the client
  keeps no item count of its own

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
   curated clips — the whole Core sequence), then prints the sequence report.
   Re-seeding is idempotent and never resets anyone's progress. Then the
   provider top-up (candidate material only — it never reaches a member): when
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
node tool/seedEmulatorHumorCatalog.cjs          # catalogue + Core sequence report
# optional licensed top-up (needs functions/.secret.local with GIPHY_API_KEY):
node tool/seedEmulatorHumorCatalog.cjs --provider-topup --functions-host 127.0.0.1:5001
node tool/humorCalibrationQa.cjs --emulator     # optional end-to-end check of V1–V15
```

Or run the whole sequence without the app:
`powershell -NoProfile -ExecutionPolicy Bypass -File tool/ensure_emulators.ps1`.
The calibration check creates and removes scratch users, but its ratings stay
in the catalogue's `stats`.
