# Mevora Boost — In-App Purchase Architecture

Boost is a **one-time consumable** that increases Discovery ranking/visibility for a configured duration (default **30 minutes**). It is not a subscription, coin wallet, or premium tier. Prices are never set in Flutter or Cloud Functions.

This document is the source of truth for IAP. Product phases still follow `MEVORA_DEVELOPMENT.md`.

---

## 1. Stores

| Platform | API | Product type |
| --- | --- | --- |
| iOS | StoreKit 2 via Flutter `in_app_purchase` | Consumable |
| Android | Google Play Billing via Flutter `in_app_purchase` | One-time in-app product (consumable) |

The client fetches `productId`, `title`, `description`, `localizedPrice`, `currency`, and availability from the store. **Never hardcode a price.**

---

## 2. Product config (placeholders)

`BoostProductConfig` (`lib/features/boost/domain/config/boost_product_config.dart` and `functions/src/boost/config.ts`):

| Field | Placeholder | Override |
| --- | --- | --- |
| `iosProductId` | `com.mevora.app.boost` | `--dart-define=BOOST_IOS_PRODUCT_ID=` / `BOOST_IOS_PRODUCT_ID` env |
| `androidProductId` | `com.mevora.app.boost` | `BOOST_ANDROID_PRODUCT_ID` |
| `duration` | 30 minutes | `BOOST_DURATION_MINUTES` / `BOOST_DURATION_MS` |
| `displayOrder` | 0 | `BOOST_DISPLAY_ORDER` |

Create these SKUs in App Store Connect and Play Console (see §10–11). Until then, local StoreKit testing can use `ios/Runner/MevoraBoost.storekit`.

---

## 3. User flow

```text
Discovery → Boost button → BoostScreen
  → load store product (localized price)
  → [ BOOST'U AKTİF ET ] / Boost'u Satın Al
  → native StoreKit / Play payment sheet
  → Flutter sends transaction to Cloud Function verifyBoostPurchase
  → server validates product, uid, transaction, duplicates
  → server activates Boost
  → Discovery (ranking bonus, filters still apply)
```

UI copy is Turkish. Loading:

1. `Satın alma işlemi başlatılıyor...`
2. `Satın alma doğrulanıyor...`

The app **must not** say Boost is active until the backend confirms.

Success: `Boost aktif! 🚀` / `Profilin daha fazla kişiye gösterilmeye başlayacak.`

Already active: `Zaten aktif bir Boost'un var.`

---

## 4. Flutter layers

```text
BoostScreen / BoostButton
  → PurchaseController
    → GetBoostProduct / PurchaseBoost / VerifyBoostPurchase / GetActiveBoost
      → PurchaseRepository
        → StorePurchaseDataSource (in_app_purchase)
        → FirebasePurchaseDataSource (callable + owner reads)
          → ApplePurchaseService / GooglePurchaseService
```

UI must not import StoreKit, Play Billing, or Firebase.

**States:** `initial`, `loading`, `productLoaded`, `purchasing`, `verifying`, `success`, `cancelled`, `failed`, `unavailable`.

---

## 5. Verification (never trust the client)

`verifyBoostPurchase` is the only writer of purchase/boost activation fields.

1. Require Firebase Auth UID. Ignore client `status`, `expiresAt`, `verifiedAt`, `purchaseId`, `userId`.
2. `PurchaseVerificationService` checks product ID against config, non-empty uid/transaction, and `purchases/{purchaseId}` idempotency (`{platform}_{transactionId}`).
3. `ApplePurchaseVerifier` calls App Store Server API (`GET /inApps/v1/transactions/{id}`), production then sandbox.
4. `GooglePurchaseVerifier` calls Play Developer API (`purchases.products.get`) and consumes the token server-side.
5. Duplicate **verified** transaction → return existing Boost, **do not** double-activate.
6. `BoostActivationService` uses `FieldValue.serverTimestamp()` + configured duration. One active Boost at a time (`allowStacking = false` for later stacking).

Emulator without store credentials still requires uid + allowed product + transaction id; it never lets the client write `boost.status=active`.

Production secrets (never commit):

- `APPLE_IAP_ISSUER_ID`, `APPLE_IAP_KEY_ID`, `APPLE_IAP_PRIVATE_KEY`
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` (Play Android Developer API)

---

## 6. Firestore models

### `purchases/{purchaseId}` (functions write only; owner read)

`purchaseId`, `userId`, `productId`, `platform`, `transactionId`, `purchaseTokenHashOrReference` (**hash**, not raw Play token), `status`, `purchasedAt`, `verifiedAt`, `createdAt`.

No cards, CVV, bank data, or receipts.

### `users/{uid}/boosts/{boostId}` (functions write only; owner read)

`boostId`, `userId`, `productId`, `purchaseId`, `status` (`pending` | `active` | `expired` | `cancelled`), `startedAt`, `expiresAt`, `createdAt`.

Other users cannot read purchases or boosts. Discovery **does not** send `isBoosted` to other clients.

---

## 7. Activation, expiration, Discovery

- Activation clock is **server time**.
- Client may show remaining minutes. Authority is `expiresAt`.
- Optional `expireBoost` (every 15 minutes) sets `status=expired`. Discovery still treats `expiresAt < now` as expired if the job lags.
- Discovery loads active boost user IDs (collection group `boosts` where `status == active`, then `expiresAt > now`) and sorts those profiles first. Distance, age, gender, prefs, and blocks still apply.
- Viewer cache: `PurchaseRepository` + `MemoryCache` (TTL ~2 minutes). Discovery hydrates once on start / returning from BoostScreen, **not every swipe**. Cache is not source of truth.

---

## 8. Restore (consumable)

| Platform | Behavior |
| --- | --- |
| iOS | StoreKit does **not** restore consumables. History is `purchases` + `users/{uid}/boosts` keyed by Firebase UID. |
| Android | Unconsumed purchases may redeliver. `verifyBoostPurchase` is idempotent; server consumes the token. |

---

## 9. Analytics

`boost_viewed`, `boost_purchase_started`, `boost_purchase_success`, `boost_purchase_cancelled`, `boost_purchase_failed`, `boost_activated`, `boost_expired`.

Never log purchase tokens, receipts, cards, or raw StoreKit/Play codes.

---

## 10. App Store Connect steps (you)

1. Agreements, Tax, and Banking — Paid Apps.
2. In-App Purchases → Consumable.
3. Product ID: `com.mevora.app.boost` (or your override).
4. Reference name, localized display name/description (Turkish + English).
5. Price tier (store-localized; Mevora never stores this).
6. Review screenshot + notes: “One-time Boost, 30 minutes extra Discovery visibility.”
7. Submit with the app binary. In-App Purchase capability is on the App ID.
8. For local Xcode testing, select `MevoraBoost.storekit`.
9. Set Cloud Functions secrets: App Store Connect API key (Issuer ID, Key ID, `.p8`).

---

## 11. Google Play Console steps (you)

1. Payments profile, tax, and banking.
2. Monetize → In-app products → Create product.
3. Product ID: `com.mevora.app.boost` (or your override).
4. Name/description; default price and tax; mark **consumable** (one-time, can be bought again).
5. Activate the product. License testers for internal testing.
6. Upload an App Bundle that includes Billing (added by `in_app_purchase`).
7. Link a Google Play Developer API service account to the Play Console; grant access; put JSON in `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`.
8. Package name must match (`com.mevora.app` production; flavors may differ — use env `ANDROID_PACKAGE_NAME`).

---

## 12. Security

- Firestore: owner **read** only on `purchases` and `users/{uid}/boosts`. All writes `if false` (Admin SDK / functions).
- Clients cannot set `boost.status`, `expiresAt`, `verifiedAt`, `purchaseId`, `transactionId`, or `userId`.
- App Check on callables outside the emulator.
- Account deletion deletes that UID’s purchases and boosts.

---

## 13. Tests

| Area | Coverage |
| --- | --- |
| `PurchaseVerificationService` | uid/product/transaction, duplicates, other-user receipt |
| `BoostActivationService` | duration, one-at-a-time, expiresAt vs now, stacking flag |
| `PurchaseRepository` | store product, cancel, verify, cache, expired cache |
| `PurchaseController` | load, success only after verify, cancel, fail, already active |
| Widgets | BoostScreen copy, button, loading, success, human errors |
| Integration (mocked) | Discovery → product → purchase → verify → activate → Discovery |

---

## 14. Intentionally out of scope

Subscriptions, coins, premium, Stripe, PayPal, client-set prices, broadcasting Boost status to other users.
