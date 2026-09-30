# Mevora Picks — cost model

Mevora is a finite daily batch, not a feed: a member meets at most
`PICKS_DAILY_TARGET` people per Istanbul day (10 by default, 15 supported),
plus a bounded replacement allowance for Picks that become ineligible. This
document models what that costs in Firestore reads, before and after the
2026-09-30 Picks cost work (PRs #153–#161), and how to measure it live.

All read counts are **billed** reads: one per document fetched (a missing one
included), one per document a query returns, and at least one per query.

## Measuring it live

Every `getMevoraPicks` call logs one line:

```
mevora_picks_cost {path, reads, documents, queries, queryDocuments, picks, targetCount, durationMs}
```

`path` is what the open did:

| path | meaning |
|---|---|
| `generation` | first open of the Istanbul day: pool scan, scoring, batch write |
| `waited` | another open of the same day was generating; this one waited for its batch |
| `reopen` | a live batch was served (the fast path) |
| `topUp` | a live batch, plus a replacement scan for a Pick that became ineligible |
| `empty` | answered before Picks (learning gate, discovery off) |

A log-based metric on `jsonPayload.message="mevora_picks_cost"` with labels
`path` and a distribution on `reads` gives generation and reopen cost
separately. The count comes from `functions/src/picks/readMeter.ts`, which
wraps the SDK's public read entry points; `functions/test/picksCost.test.cjs`
pins the same numbers against a metered in-memory Firestore.

## Symbols

| symbol | meaning |
|---|---|
| T | daily target (10 or 15) |
| K | Picks still active in today's batch at reopen (≤ T + replacements) |
| P | profiles the generation scan reads: ≤ 16·T (4 pages of 40 at T=10, 6 at T=15) |
| f₁ | share of scanned profiles the profile document alone admits (gender the viewer wants, age range, photos, moderation) — ~0.4 in a two-sided pool |
| f₂ | share also admitted by account, activity and the candidate's own preferences — ~0.25 |
| f₃ | share also inside the 100 km gate — ~0.2 |
| L, Pa, M | the viewer's likes, passes and active matches (history) |
| B | live Boosts in the whole system |
| D, O | daily active members, Picks opens per active member per day |

## Before (main at e9f6a82)

Every open loaded the whole viewer context first:

```
open_fixed_before   ≈ 14 + L + Pa + M + B + (viewer's blocks, ≥3)
revalidate_before   ≈ 9·K          # profile, users×2, prefs, location, isBlocked ×4
REOPEN_before       ≈ open_fixed_before + 9·K
GENERATION_before   ≈ open_fixed_before + P·4 (users×2, prefs, location for every scanned profile)
                      + 4·(active, undecided scanned)   # isBlocked
                      + 4·(eligible)                    # music + relationship, viewer side re-read per candidate
                      + 2·(floor-passing) (humor) + 9·T (revalidating the new batch) + cursor reads
```

Measured by simulation (3,000 members, 5 % boosting ⇒ B ≈ 150, a viewer in
Istanbul; `node tool/simulatePicksCost.cjs <main checkout>/functions [T]`):

| code | T | generation, no history | generation, 300 likes + 300 passes | reopen (full batch), no history | reopen, 300 + 300 |
|---|---|---|---|---|---|
| main | 6 (live) | 1,669 | 2,267 | 196 (mean) | 794 |
| main, config only | 10 | 1,678 | 2,276 | 261 | 859 |
| main, config only | 15 | 2,303 | 2,901 | 270 | 868 |

## After (preview with #153–#161)

```
open_fixed_after    = 12                     # account, learning, prefs, profile, location, language, batch, …
REOPEN_after        = 5·K + 12               # profile, users, prefs, location, their-side block per Pick
                                             #  + 3 pair-decision queries + 2 block queries (K ≤ 15)
GENERATION_after    ≈ 12 + 2 (lease) + 2 (viewer summaries) + 2 (viewer humor)
                      + P                                  # the page queries
                      + 2·f₁·P                             # users + prefs, profile-admitted only
                      + f₂·P                               # location, chain-admitted only
                      + f₃·P + 6·pages                     # their-side block read + pair/Boost queries
                      + 2·f₃·P·(viewer has music/relationship data)
                      + 2·(floor-passing)·(viewer calibrated humor)
```

Nothing in either formula grows with the member's history (L, Pa, M) or with
the number of live Boosts in the system (B).

| code | T | generation (simulated mean / max) | reopen, K = T |
|---|---|---|---|
| preview | 10 | **511 / 558** | **62** |
| preview | 15 | **727 / 783** | **87** |

Verified on the Firestore emulator with the real SDK: a reopen with K = 2
logged exactly `reads: 22` (= 5·2 + 12).

### What each PR removed

| PR | change | effect (target 10, 30-candidate test pool) |
|---|---|---|
| #153 | open-ended deck callable retired | no unbounded feed; no deck scans at all |
| #154 | sizing from one knob, batch stores its size | — (contract) |
| #155 | one generation per member per day (lease); replacement scans only for ineligible Picks, claimed, with backoff | two concurrent opens: 2 scans → 1; low-supply rescans: every 30 min → never |
| #156 | reopen without history (pair lookups) | reopen 94 → 90, and 741 → 90 with 300+300 history + 50 Boosts |
| #157 | each document once per request | generation 466 → 237, reopen 90 → 80 |
| #158 | decisions and blocks per candidate | generation 237 → 147, reopen 80 → 52; generation no longer grows with history |
| #159 | Boost per page, not system-wide | generation independent of B (needs the `boosts (status, userId)` index) |
| #160 | cheapest-first page narrowing | mixed page 172 → 118 |
| #161 | this measurement | — |

## Daily totals for Picks (reads per day)

`PICKS_DAY = D · GENERATION + D · (O − 1) · REOPEN (+ replacement scans, rare)`

Worst-case reopen uses K = T (a full batch); generation uses the simulated
mean; "before" uses a member with no history (a real, older member base costs
more before and the same after).

| scenario | before (main) | after (preview) |
|---|---|---|
| 3,000 registered, **600 DAU, 1 open**, T = 10 | 600 · 1,678 = **1.01 M** | 600 · 511 = **0.31 M** |
| 3,000 registered, **600 DAU, 3 opens**, T = 10 | 1.01 M + 600·2·261 = **1.32 M** | 0.31 M + 600·2·62 = **0.38 M** |
| **3,000 DAU, 1 open**, T = 10 | **5.03 M** | **1.53 M** |
| **3,000 DAU, 3 opens**, T = 10 | 5.03 M + 1.57 M = **6.60 M** | 1.53 M + 0.37 M = **1.91 M** |
| 3,000 DAU, 1 open, **T = 15** | **6.91 M** | **2.18 M** |
| 3,000 DAU, 3 opens, **T = 15** | 6.91 M + 1.62 M = **8.53 M** | 2.18 M + 0.52 M = **2.70 M** |
| **low supply**: 30 % of 3,000 DAU short, 3 opens ≥ 30 min apart, T = 10 | + 900 · 2 · ~1,500 = **+2.7 M** rescans | **+0** (a short batch stays short) |
| **fast path only** (reopen), 3,000 DAU · 2 extra opens | 3,000 · 2 · 261 = **1.57 M** (B = 150; +598 per member with 300+300 history) | 3,000 · 2 · 62 = **0.37 M**, flat |

At an Istanbul-day boundary every active member regenerates once; with the
generation lease a burst of concurrent opens still costs one scan each.

Replacement scans run only when a Pick became ineligible (block, deletion,
hidden, suspension, out of range), at most once per ineligible Pick, within
the day's ceiling (T + ⌈T/4⌉), with a 30 min → 1 h → 2 h → 4 h backoff when
they find nobody.

## Still open (not done here)

- **Server-owned candidate projection** (`discoveryCandidates/{uid}`): would
  turn the ~4 documents read per admissible candidate into 1. Needs triggers
  on four collections and a backfill of every member — a production
  migration, owner-run.
- **Gender in the pool query**: a composite index `(isDiscoverable,
  profileCompleted, gender, updatedAt)` would skip wrong-gender profiles
  before they are read at all (f₁ ≈ 0.4 ⇒ up to ~60 % fewer page reads).
- **`boosts (status, userId)` index**: declared in `firestore.indexes.json`;
  until it is deployed, Boost lookups fall back to the global list.
- **`expireBoost`** reads every live Boost every 15 minutes (96 · B reads a day).

## Beyond Picks — decisions, chat, images, startup

These are read from the code on `preview` (2026-09-30), **not measured**, and
are outside the Picks changes above. They are here so the daily total has all
its terms; each flagged item is its own follow-up, independent of Picks.

**Symbols:** A = the member's active matches, N = messages in a chat,
S = image bytes served, m = cache misses.

### Decisions (`recordDiscoveryDecision`)

| operation | reads | writes | notes |
|---|---|---|---|
| pass | ≈ 11 + A (+14–16 learning trigger) | 2 (+2 if it was a Pick, +3 learning) | `loadActiveMatchPartnerIds` has no limit |
| like, no match | ≈ 17 + A (+14–16) | 2 (+ up to 4) | includes the incoming-like push |
| like that creates a match | ≈ 26 + A + ~55 in triggers | ≈ 19 | compatibility snapshot, bonus, 2 pushes, 2 learning events |

`DECISIONS_DAY ≈ passes · (27 + A) + likes · (33 + A) + matches · ~80` reads.
With a finite day of T Picks a member can make at most T + ⌈T/4⌉ Picks
decisions a day (e.g. 3,000 DAU × 10 decisions ≈ 0.9 M reads at A ≈ 5).

### Chat

| operation | reads | writes |
|---|---|---|
| open a chat | ≈ 42 (30 latest messages + match, typing, presence, privacy, block check, E2EE identity) | 1 + 2·unread |
| send a message (client + `sendMessageNotification`) | ≈ 10 + min(40, N) | 6 |
| each message, per open listener | ≈ 3–6 (message, receipts, match doc twice) | 2 (delivered, read) |
| presence heartbeat | 1 per listening partner per write | **1 every 30 s in foreground** |
| inbox (from app start, always on) | **A + A presence listeners, no limit**, re-subscribed on every resume | 0 |

`CHAT_DAY ≈ opens · 42 + sent · (10 + min(40, N) + fan-out) + foreground_minutes · 2 · (1 + online partners)`

### Images

- No thumbnails are generated (`thumbUrl` is always null). Every surface
  (Picks card, chat avatar, profile) loads the original: up to 1080 px at
  JPEG q85, roughly 150–400 KB (estimated, not measured).
- No `Cache-Control` on uploaded photos, and no disk image cache in the app
  (only Flutter's in-memory cache, 80 images / 32 MB). A cold start re-downloads
  every original it shows.
- E2EE chat media is re-downloaded on every snapshot of the message window.

`IMAGES_DAY ≈ Σ cache misses · S`. For a Picks day, about
DAU · opens · (T cards + photos opened) · S. For example, 3,000 DAU · 3 opens
· 10 cards · 250 KB ≈ **22 GB/day of Storage egress**, most of which a 320 px
thumbnail (≈ 20–30 KB) and a disk cache would remove.

### Startup (signed in)

≈ 17 + 2·A reads and 5–7 writes per cold start, before Picks. That includes
2 listeners for users/profiles, the app config, the unbounded inbox and
presence, and a language-sync write that repeats on every users/profiles
snapshot.
