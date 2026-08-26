# Mevora Boost — In-App Purchase Architecture

Boost is a **one-time consumable time grant** that increases Discovery ranking/visibility for **7, 30, or 365 days**. It is not an auto-renewing subscription, generic coin wallet, or premium tier.

Charged prices always come from StoreKit / Play Billing. Never hard-code a charge amount in Flutter.

This document is the source of truth for IAP. Product phases still follow `MEVORA_DEVELOPMENT.md`.

---

## 1. Stores

| Platform | API | Product type |
| --- | --- | --- |
| iOS | StoreKit 2 via Flutter `in_app_purchase` | Consumable |
| Android | Google Play Billing via Flutter `in_app_purchase` | One-time in-app product (consumable) |

Consumable (not subscription) because the user can buy again and **must not** be billed automatically when Boost expires.

The client fetches `productId`, `title`, `description`, `localizedPrice`, and `currency` from the store. **Never charge a hardcoded price.**

---

## 2. Pack catalog

Live catalog: Firestore `boostProducts/{sku}` (authenticated read, **no client write**). Cloud Functions `resolveBoostPack` reads this first, then Dart/Functions defaults.

| SKU | Duration | Storefront |
| --- | --- | --- |
| `mevora_boost_7_days` | 7 days | yes |
| `mevora_boost_1_month` | 30 days | yes |
| `mevora_boost_1_year` | 365 days | yes |
| `com.mevora.app.boost.1` / `.5` / `.10` / `com.mevora.app.boost` | legacy 30-minute wallet credit | hidden |

Create the three storefront SKUs in App Store Connect and Play Console with **the same product IDs** on both stores. Local StoreKit testing: `ios/Runner/MevoraBoost.storekit`.

---

## 3. User flow

```text
Profile "Öne Çıkar" / Settings "Satın Alma Geçmişi" / Discovery Boost
  → BoostScreen
  → load catalog + store prices + active Boost + history
  → buy 1 Week / 1 Month / 1 Year
  → native StoreKit / Play payment sheet
  → Flutter sends transaction to Cloud Function verifyBoostPurchase
  → server validates product, uid, transaction, duplicates
  → server sets startedAt / expiresAt (stacks remaining time)
  → Discovery ranking bonus (filters still apply)
```

The app **must not** say Boost is active until `verifyBoostPurchase` confirms.

Purchase success: `Boost aktif! 🚀`

Active Boost: buying again **adds** the new duration onto remaining time. The same store transaction is never applied twice.

---

## 4. Flutter layers

```text
BoostScreen / BoostButton / Profile "Öne Çıkar"
  → PurchaseController
    → GetBoostProducts / PurchaseBoost / VerifyBoostPurchase
      / GetActiveBoost / GetBoostHistory / Restore
      → PurchaseRepository
        → StorePurchaseDataSource (in_app_purchase)
        → FirebasePurchaseDataSource (callable + owner reads)
          → ApplePurchaseService / GooglePurchaseService
```

UI must not import StoreKit, Play Billing, or Firebase.

**States:** `initial`, `loading`, `productLoaded`, `purchasing`, `verifying`, `credited` (legacy wallet only), `activating` (legacy wallet only), `success`, `cancelled`, `failed`, `unavailable`.

---

## 5. Verification (never trust the client)

`verifyBoostPurchase` is the only writer of purchase fields and Boost `status` / `expiresAt` for store packs.

1. Require Firebase Auth UID. Ignore client `status`, `expiresAt`, `verifiedAt`, `purchaseId`, `userId`.
2. `PurchaseVerificationService` checks product ID against the catalog, non-empty uid/transaction, and `purchases/{purchaseId}` idempotency (`{platform}_{transactionId}`).
3. `ApplePurchaseVerifier` calls App Store Server API (`GET /inApps/v1/transactions/{id}`), production then sandbox.
4. `GooglePurchaseVerifier` calls Play Developer API (`purchases.products.get`) and consumes the token server-side.
5. Duplicate **verified** transaction → return existing Boost, **do not** add time again.
6. New verified duration pack → `BoostActivationService` sets `expiresAt = max(now, currentExpiresAt) + pack.duration` using **server time**.
7. Legacy wallet SKUs still credit `users/{uid}/boostWallet/current`. `activateBoost` consumes one leftover credit (30 minutes) and may stack.

Production secrets (never commit):

- `APPLE_IAP_ISSUER_ID`, `APPLE_IAP_KEY_ID`, `APPLE_IAP_PRIVATE_KEY`
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` (Play Android Developer API)

---

## 6. Firestore models

### `purchases/{purchaseId}` (functions write only; owner read)

`purchaseId`, `userId`, `productId`, `durationDays`, `durationMs`, `boostCount`, `platform`, `transactionId`, `purchaseTokenHashOrReference` (**hash**, not raw Play token), `status`, `purchasedAt`, `verifiedAt`, `createdAt`.

No cards, CVV, bank data, or receipts.

### `users/{uid}/boosts/{boostId}` (functions write only; owner read)

`boostId`, `userId`, `productId`, `purchaseId`, `status` (`pending` | `active` | `expired` | `cancelled`), `startedAt`, `expiresAt`, `createdAt`.

### `users/{uid}/boostWallet/current` (functions write only; owner read)

Legacy leftover credits only.

Other users cannot read purchases or boosts. Discovery **does not** send `isBoosted` to other clients.

---

## 7. Activation, expiration, Discovery

- Activation clock is **server time**.
- Client may show remaining days. Authority is `expiresAt`.
- `expireBoost` (every 15 minutes) sets `status=expired`. Discovery still treats `expiresAt < now` as expired if the job lags.
- Production Discovery (`getDiscoveryCandidates`) loads active boost user IDs and sorts those profiles first. Distance, age, gender, prefs, and blocks still apply.
- Boost never means “show to everyone”.

---

## 8. Restore

| Platform | Behavior |
| --- | --- |
| iOS | Unfinished StoreKit transactions can be recovered. Finished consumables are **not** redelivered. Active Boost is `users/{uid}/boosts` keyed by Firebase UID. |
| Android | Unconsumed purchases may redeliver. `verifyBoostPurchase` is idempotent; server consumes the token. |

“Restore purchases” re-syncs the store, verifies unfinished transactions, then reloads Firebase.

A user on a new device with the same Mevora account sees active Boost from Firestore.

---

## 9. Analytics

`boost_page_opened`, `boost_viewed`, `boost_product_selected` (`product_id` only), `boost_purchase_started`, `boost_purchase_success`, `boost_purchase_cancelled`, `boost_purchase_failed`, `boost_activated`, `boost_expired`.

Never log purchase tokens, receipts, cards, or raw StoreKit/Play codes.

---

## 10. App Store Connect steps (you)

1. Agreements, Tax, and Banking — Paid Apps.
2. In-App Purchases → **Consumable** (not auto-renewable subscription).
3. Product IDs: `mevora_boost_7_days`, `mevora_boost_1_month`, `mevora_boost_1_year`.
4. Localized name/description (Turkish + English).
5. Price tier (store-localized; Mevora never stores this).
6. Review notes: “One-time Boost that increases Discovery visibility for 7 / 30 / 365 days. Not a subscription.”
7. Submit with the app binary. In-App Purchase capability is on the App ID.
8. For local Xcode testing, select `MevoraBoost.storekit`.
9. Set Cloud Functions secrets: App Store Connect API key (Issuer ID, Key ID, `.p8`).

---

## 11. Google Play Console steps (you)

1. Payments profile, tax, and banking.
2. Monetize → In-app products → Create product (**one-time**, consumable — not a subscription).
3. Product IDs: `mevora_boost_7_days`, `mevora_boost_1_month`, `mevora_boost_1_year`.
4. Name/description; default price and tax; activate.
5. License testers for internal testing.
6. Upload an App Bundle that includes Billing (`com.android.vending.BILLING`).
7. Link a Google Play Developer API service account; put JSON in `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`.
8. Package name must match (`com.mevora.app`).

---

## 12. Security

- Firestore: owner **read** only on `purchases`, `users/{uid}/boosts`, `users/{uid}/boostWallet`. `boostProducts` authenticated read. All writes `if false` (Admin SDK / functions).
- Clients cannot set `boost.status`, `expiresAt`, `verifiedAt`, `purchaseId`, `transactionId`, `userId`, or `boostBalance`.
- App Check on callables outside the emulator.
- Account deletion deletes that UID’s purchases, boosts, and wallet.

---

## 13. Tests

Use Play license testers and App Store sandbox / TestFlight before charging real money.

Covered in unit/widget tests: catalog, stacking, idempotent verify, cancel, store down, restore, history UI.

---

## 14. Intentionally out of scope

Auto-renewing subscriptions, generic coins, premium, Stripe, PayPal, client-set prices, broadcasting Boost status to other users, collecting card data in the app.
