# Music Compatibility Engine — Integration Report

**Date:** 2026-08-23  
**Scope:** Extend existing Spotify OAuth + music profile pipeline with named shared-item insights, optional playlist overlap, Discover UI, and TR/EN localization — without rewriting MatchEngine.

---

## Spotify Integration

| Check | Result | Notes |
| --- | --- | --- |
| OAuth | **PASS** | Existing PKCE link flow kept (`spotifyLinkMusic`). Music scopes extended with `playlist-read-private` (reconnect required for playlist signal). |
| Data sync | **PASS** | `syncSpotifyTaste` + 6h `lastSyncedAt` throttle unchanged. Playlist fetch soft-fails if scope missing. |
| Music profile | **PASS** | Still `users/{uid}/music/summary` + minimized `musicProfile` IDs. Tokens remain in `spotifySecrets/{uid}` (Admin only). `musicProfileVersion: 2`. |

### Spotify data actually used (no fabrication)

| Signal | Source | Notes |
| --- | --- | --- |
| Top tracks / artists | `/me/top/*` medium_term | IDs + display names cached |
| Recently played | `/me/player/recently-played` | Recency overlap only |
| Genres | Artist `genres` | Aggregated shares |
| Playlists | `/me/playlists` + track IDs | Only when playlist scope granted |
| Play counts / listen duration | **Not available** | Never invented |

---

## Music Engine

| Check | Result | Notes |
| --- | --- | --- |
| Shared tracks | **PASS** | ID intersection + name resolve from cached catalogs |
| Shared artists | **PASS** | Same |
| Playlist analysis | **PASS** | Optional; weight 10% only when **both** users have `playlistTrackIds` |
| Genre analysis | **PASS** | Jaccard-style overlap on genre names |
| Compatibility score | **PASS** | Deterministic; unit-tested client + Functions |
| Dynamic insights | **PASS** | Machine codes → TR/EN via `MusicInsightLocalizer` |

### Score formula

**Without playlist data (unchanged):** tracks 40% · artists 30% · genres 20% · recent 10%

**With playlist data on both sides:** tracks 35% · artists 25% · genres 20% · playlist 10% · recent 10%

---

## Mevora Integration

| Check | Result | Notes |
| --- | --- | --- |
| Matching Engine integration | **PASS** | Music remains optional `musicScore` input to `calculateCompatibility` (15% when present). MatchEngine / mutual-like rules untouched. |
| Discover integration | **PASS** | `getDiscoveryCandidates` emits named shares + insight codes; client parses into `DiscoveryCandidate`; badge opens insight sheet. |
| Localization | **PASS** | New ARB keys EN/TR via UTF-8 Dart merge (`tool/merge_music_l10n.dart`). |

### Wiring

```
Spotify OAuth → sync → users/{uid}/music/summary
                              ↓
                    musicScoreForPair (Functions)
                              ↓
              Mevora Compatibility (+ music 15% when present)
                              ↓
                    Discover card + Music Match sheet
```

Spotify-disconnected users stay in Discover; music fields are simply null/empty.

---

## Privacy & Security

| Check | Result | Notes |
| --- | --- | --- |
| Token security | **PASS** | Access/refresh tokens stay server-side in `spotifySecrets` |
| Data minimization | **PASS** | Profile stores IDs + limited named top items; max 200 playlist track IDs |
| Privacy Policy compatibility | **PASS** | Hosting policy already covers “optional Spotify music taste signals” |

---

## Automated tests run

- `flutter test test/features/music/` — all passed
- `node --test test/musicCompatibility.test.cjs` — all passed
- `tsc` (functions) — passed

### Manual / device tests (require live Spotify accounts)

Tests 1–12 from the brief (two Spotify users, disconnect, token expiry, Discover without Spotify) need real OAuth + deploy of Functions.

---

## Changed files (primary)

### Functions
- `functions/src/musicCompatibility.ts` — score, insights, name resolve, playlist weights
- `functions/src/spotifyMusic.ts` — playlist sync, enriched pair scoring, same-taste payload
- `functions/src/backend.ts` — Discover music detail fields
- `functions/test/musicCompatibility.test.cjs`

### Flutter
- `lib/features/music/domain/services/music_compatibility.dart`
- `lib/features/music/domain/services/music_insight_localizer.dart`
- `lib/features/music/domain/entities/music_taste.dart`
- `lib/features/music/presentation/widgets/music_compatibility_badge.dart`
- `lib/features/music/presentation/widgets/music_compatibility_sheet.dart`
- `lib/features/music/presentation/pages/music_page.dart`
- `lib/features/music/data/datasources/functions_music_data_source.dart`
- `lib/features/authentication/data/services/spotify_auth_service.dart` — playlist scope
- `lib/features/discovery/domain/entities/discovery_candidate.dart`
- `lib/features/discovery/data/repositories/discovery_repository_impl.dart`
- `lib/features/discovery/data/repositories/hybrid_discovery_repository.dart`
- `lib/features/discovery/presentation/pages/discovery_profile_details_page.dart`
- `lib/features/discovery/presentation/widgets/discovery_profile_card.dart`
- `lib/l10n/app_en.arb`, `app_tr.arb` (+ generated)
- `tool/music_l10n_*.json`, `tool/merge_music_l10n.dart`
- `test/features/music/music_compatibility_test.dart`

---

## Deploy note

Redeploy Cloud Functions (`getDiscoveryCandidates`, Spotify music callables) so Discover receives named shares and insights. Existing Spotify users must **reconnect** once to grant playlist scope; until then playlist overlap stays unavailable (base weights still apply).
