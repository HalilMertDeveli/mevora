# Smart Boost

Mevora Smart Boost raises visibility **among compatible, active candidates** —
not random everyone.

## Product packs

| Pack | Product ID | Duration |
|------|------------|----------|
| Starter | `mevora_smart_boost_30m` | 30 minutes |
| Popular | `mevora_smart_boost_1h` | 1 hour |
| Power | `mevora_smart_boost_24h` | 24 hours |

Prices come from App Store / Play / Firestore `boostProducts` — never hard-coded.

## Purchase flow

1. Client opens Boost screen → logs `boost_viewed`
2. `getSmartBoostPreview` returns **real** eligible-active counts + profile quality
3. User buys via existing IAP → `verifyBoostPurchase`
4. Duration packs auto-activate; server sets `expiresAt` (device clock ignored)
5. `expireBoost` scheduler marks expired boosts

## Ranking

Existing Discover sort preserved:

1. Question alignment tier
2. Distance
3. Base score × Smart Boost multiplier (~1.25) when boosted
4. Diversify boosted / non-boosted within tier

Hard filters (gender, age, blocks, likes/passes, matches, inactive, photos, etc.)
are **never** bypassed.

## Preview counts

Computed server-side from the same hard-filter pool:

- `suitableActiveCount` — eligible + active in last 30 minutes
- `activeUserCount` — recently active scanned users
- `newUsersLast30m` — new profiles in last 30 minutes

No fake scarcity.

## Profile quality

Shown as advice only on the Smart Boost screen. Never blocks purchase.
Spotify is an optional bonus, not a penalty.

## Analytics

Uses existing `AnalyticsEvents`:

- `boost_viewed` / `boost_page_opened`
- `boost_purchase_started` / `boost_purchase_success`
- `boost_activated` (+ alias `boost_started`)
- `boost_expired` (+ alias `boost_completed`)
- `boost_match` / `boost_like` (for funnel wiring)
