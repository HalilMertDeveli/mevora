# Mevora Boost — In-App Purchase Architecture

Boost is a **consumable pack** that credits a Boost balance, then an activation that increases Discovery ranking/visibility for a configured duration (default **30 minutes** per activation). It is not a subscription, generic coin wallet, or premium tier. Charged prices always come from StoreKit / Play Billing. Catalog TRY amounts are **display fallbacks only**.

This document is the source of truth for IAP. Product phases still follow `MEVORA_DEVELOPMENT.md`.

---

## 1. Stores

| Platform | API | Product type |
| --- | --- | --- |
| iOS | StoreKit 2 via Flutter `in_app_purchase` | Consumable |
| Android | Google Play Billing via Flutter `in_app_purchase` | One-time in-app product (consumable) |

The client fetches `productId`, `title`, `description`, `localizedPrice`, `currency`, and availability from the store. Catalog `fallbackPriceAmount` values (49.99 / 199.99 / 349.99 TRY) are shown only when the store has not returned a price. **Never charge a hardcoded price.**

---

## 2. Pack catalog (source of truth)

Live catalog: Firestore `boostProducts/{sku}` (authenticated read, **no client write**). Cloud Functions `resolveBoostPack` reads this first, then Dart/Functions defaults.

Offline fallback + Remote Config key `boostCatalogJson` (not a security control):

| SKU | Boosts | Fallback display |
| --- | --- | --- |
| `com.mevora.app.boost.1` | 1 | ₺49,99 |
| `com.mevora.app.boost.5` | 5 | ₺199,99 |
| `com.mevora.app.boost.10` | 10 | ₺349,99 |
| `com.mevora.app.boost` | 1 | legacy single SKU, still accepted |

`BoostProductConfig` still accepts `--dart-define=BOOST_IOS_PRODUCT_ID=` / `BOOST_ANDROID_PRODUCT_ID` for the legacy id. Duration remains **30 minutes** (`BOOST_DURATION_MINUTES` / `BOOST_DURATION_MS`).

Create the three pack SKUs in App Store Connect and Play Console (see §10–11). Until then, local StoreKit testing can use `ios/Runner/MevoraBoost.storekit`.

---

## 3. User flow

```text
Profile "Öne Çıkar" / Discovery Boost button → BoostScreen
  → load catalog (Firestore, else defaults) + store prices + wallet + history
  → buy a pack (1 / 5 / 10)
  → native StoreKit / Play payment sheet
  → Flutter sends transaction to Cloud Function verifyBoostPurchase
  → server validates product, uid, transaction, duplicates
  → server credits Boost balance (does not activate)
  → [ Boost'u aktif et ] consumes 1 from wallet via activateBoost
  → Discovery (ranking bonus, filters still apply)
```

UI copy is Turkish (English l10n included). Loading:

1. `Satın alma işlemi başlatılıyor...`
2. `Satın alma doğrulanıyor...`
3. `Boost aktif ediliyor...`

The app **must not** say Boost is active until `activateBoost` confirms.

Purchase success: `Boost hesabına eklendi`

Activation success: `Boost aktif! 🚀` / `Profilin daha fazla kişiye gösterilmeye başlayacak.`

Already active: `Zaten aktif bir Boost'un var.`

Insufficient balance: `Aktif etmek için Boost bakiyen yok.`

---

## 4. Flutter layers

```text
BoostScreen / BoostButton / Profile "Öne Çıkar"
  → PurchaseController
    → GetBoostProducts / PurchaseBoost / VerifyBoostPurchase / ActivateBoost
      / GetActiveBoost / GetBoostWallet / GetBoostHistory
      → PurchaseRepository
        → StorePurchaseDataSource (in_app_purchase)
        → FirebasePurchaseDataSource (callable + owner reads)
          → ApplePurchaseService / GooglePurchaseService
```

UI must not import StoreKit, Play Billing, or Firebase.

**States:** `initial`, `loading`, `productLoaded`, `purchasing`, `verifying`, `credited`, `activating`, `success`, `cancelled`, `failed`, `unavailable`.

---

## 5. Verification (never trust the client)

`verifyBoostPurchase` is the only writer of purchase/wallet credit fields. `activateBoost` is the only writer of activation `status` / `expiresAt`.

1. Require Firebase Auth UID. Ignore client `status`, `expiresAt`, `verifiedAt`, `purchaseId`, `userId`, `balance`.
2. `PurchaseVerificationService` checks product ID against the catalog, non-empty uid/transaction, and `purchases/{purchaseId}` idempotency (`{platform}_{transactionId}`).
3. `ApplePurchaseVerifier` calls App Store Server API (`GET /inApps/v1/transactions/{id}`), production then sandbox.
4. `GooglePurchaseVerifier` calls Play Developer API (`purchases.products.get`) and consumes the token server-side.
5. Duplicate **verified** transaction → return existing wallet, **do not** double-credit.
6. `BoostCreditService` adds `boostCount` from the catalog to `users/{uid}/boostWallet/current`.
7. `activateBoost` consumes 1 from wallet. `BoostActivationService` uses `FieldValue.serverTimestamp()` + configured duration. One active Boost at a time (`allowStacking = false`).

Emulator without store credentials still requires uid + allowed product + transaction id; it never lets the client write `boost.status=active` or `boostBalance`.

Production secrets (never commit):

- `APPLE_IAP_ISSUER_ID`, `APPLE_IAP_KEY_ID`, `APPLE_IAP_PRIVATE_KEY`
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` (Play Android Developer API)

---

## 6. Firestore models

### `purchases/{purchaseId}` (functions write only; owner read)

`purchaseId`, `userId`, `productId`, `boostCount`, `platform`, `transactionId`, `purchaseTokenHashOrReference` (**hash**, not raw Play token), `status`, `purchasedAt`, `verifiedAt`, `createdAt`.

No cards, CVV, bank data, or receipts.

### `users/{uid}/boostWallet/current` (functions write only; owner read)

`balance`, `updatedAt`. Clients cannot increment or set this.

### `users/{uid}/boosts/{boostId}` (functions write only; owner read)

`boostId`, `userId`, `productId`, `purchaseId`, `status` (`pending` | `active` | `expired` | `cancelled`), `startedAt`, `expiresAt`, `createdAt`.

Other users cannot read purchases or boosts. Discovery **does not** send `isBoosted` to other clients.

---

## 7. Activation, expiration, Discovery

- Activation clock is **server time**.
- Client may show remaining minutes and wallet balance. Authority is `expiresAt` and Functions-owned `balance`.
- Optional `expireBoost` (every 15 minutes) sets `status=expired`. Discovery still treats `expiresAt < now` as expired if the job lags.
- Production Discovery (`getDiscoveryCandidates`) loads active boost user IDs (collection group `boosts` where `status == active`, then `expiresAt > now`) and sorts those profiles first. Distance, age, gender, prefs, and blocks still apply.
- Dev mock discovery persists Boost state in Firestore so production ranking works; mock deck ranking of other users is opt-in (`MockDiscoveryRepository.boostedUids`) and is **not** wired to live Boost documents.
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
3. Product IDs: `com.mevora.app.boost.1`, `com.mevora.app.boost.5`, `com.mevora.app.boost.10` (and legacy `com.mevora.app.boost` if already created).
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
3. Product IDs: `com.mevora.app.boost.1`, `com.mevora.app.boost.5`, `com.mevora.app.boost.10` (and legacy `com.mevora.app.boost` if already created).
4. Name/description; default price and tax; mark **consumable** (one-time, can be bought again).
5. Activate the product. License testers for internal testing.
6. Upload an App Bundle that includes Billing (added by `in_app_purchase`).
7. Link a Google Play Developer API service account to the Play Console; grant access; put JSON in `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`.
8. Package name must match (`com.mevora.app` production; flavors may differ — use env `ANDROID_PACKAGE_NAME`).

---

## 12. Security

- Firestore: owner **read** only on `purchases`, `users/{uid}/boosts`, `users/{uid}/boostWallet`. `boostProducts` authenticated read. All writes `if false` (Admin SDK / functions).
- Clients cannot set `boost.status`, `expiresAt`, `verifiedAt`, `purchaseId`, `transactionId`, `userId`, or `boostBalance`.
- App Check on callables outside the emulator.
- Account deletion deletes that UID’s purchases, boosts, and wallet.

---

## 13. Tests

| Area | Coverage |
| --- | --- |
| `PurchaseVerificationService` | uid/product/transaction, duplicates, other-user receipt, pack SKUs |
| `BoostCreditService` | pack count, idempotent credit, invalid SKU |
| `BoostActivationService` | duration, one-at-a-time, expiresAt vs now, stacking flag, insufficient balance |
| `PurchaseRepository` | store product, pack catalog fallbacks, cancel, verify credit, cache, expired cache |
| `PurchaseController` | load packs, credit only after verify, activate only after server, cancel, fail |
| Widgets | BoostScreen copy, button, pack sheet, history, active badge, loading, success, human errors |
| Integration (mocked) | Discovery → pack → purchase → verify → credit → activate → Discovery |

---

## 14. Intentionally out of scope

Subscriptions, generic coins, premium, Stripe, PayPal, client-set prices, broadcasting Boost status to other users.
