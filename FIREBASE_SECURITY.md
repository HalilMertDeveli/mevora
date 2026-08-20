# Firebase security

Rules live in `firebase/firestore.rules` and `firebase/storage.rules`. Field-level notes also appear in `FIRESTORE_SECURITY.md`. Architecture: `FIREBASE_ARCHITECTURE.md`. Setup: `FIREBASE_SETUP.md`.

**Never** `allow read, write: if true;`. Unknown paths fall through to `allow read, write: if false`.

## Identity

- Primary key is `request.auth.uid` (Firebase Auth UID).
- Email, phone, and display name are attributes, never document IDs and never admin gates.
- Custom claims for admin come later. Clients cannot set `accountStatus`, `isBanned`, or `isVerified`.
- Phone OTP is issued and checked by Firebase Auth only. Do not generate, persist, or log OTP values.

## Private data (owner-only)

| Path | Client |
| --- | --- |
| `users/{uid}` | Owner read/create/update. No delete (use `deleteUserAccount`). |
| `userSettings/{uid}`, `userPreferences/{uid}`, `userPrivacy/{uid}` | Owner only |
| `userLocation/{uid}` | Owner only. Other clients never receive lat/lng/geohash. Distance is `getDistanceLabel` / `getDiscoveryFeed`. |
| `users/{uid}/devices/{deviceId}` and `fcmTokens` | Owner only. Tokens are not public. |
| `purchases/{id}`, `users/{uid}/boosts/{id}`, `users/{uid}/boostWallet/current` | Owner read. **Write: none** (Functions). |
| `boostProducts/{sku}` | Authenticated read. **Write: none**. |

`profiles/{uid}` is a public dating card for authenticated users. It must not contain password, phone, private email, GPS, or FCM tokens.

## Chat, matches, calls

- `likes` and `matches` are created by Cloud Functions (`recordSwipe`), not by the client.
- Messages: participants only; `senderId == request.auth.uid`; match must be active; not blocked; text ≤ 2000.
- `calls/{id}`: clients do not write call documents. Callables + Admin SDK write signaling/state/history. No media in Firestore.
- `notifications/{id}`: functions create; recipient may update `isRead` / `readAt` only.

## Boost / IAP

Clients never write `status`, `expiresAt`, `verifiedAt`, `purchaseId`, `transactionId`, or wallet `balance` on boosts or purchases. `verifyBoostPurchase` is authoritative for credit. `activateBoost` consumes one server-owned Boost from the wallet.

## Storage

Path: `users/{uid}/profile/` (pending, approved, thumbs). Owner upload/delete. Authenticated read of approved/thumbs.

Allowed types: `image/jpeg`, `image/jpg`, `image/png`, `image/webp`. Max **5 MB**. The client resizes/compresses before upload (`ProfileImagePipeline`, max edge 1080).

Chat images: `users/{uid}/chat/{matchId}/{messageId}` — owner write; match participants read.

## App Check

| Environment | Android | Apple |
| --- | --- | --- |
| Development / staging | Debug provider | Debug provider |
| Production | Play Integrity | App Attest |

Register **debug tokens** from local devices in App Check → Apps. Do not commit debug tokens or production App Check secrets. Callables enforce App Check when not on the emulator.

DeviceCheck is not used in production; App Attest is.

## Analytics

Events only (`app_open`, `sign_up`, `login`, swipe/match/message/boost, …). UID may be set as Analytics user id. **Forbidden parameters:** email, phone, OTP, GPS, message body, FCM tokens. The Flutter adapter strips those keys.

## Cost / abuse

Do not query every user from the client. Do not write GPS on a tight timer. Attach a chat listener only for the open thread.
