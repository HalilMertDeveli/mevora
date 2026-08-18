# Mevora Firebase Data Architecture

Canonical overview: **`FIREBASE_ARCHITECTURE.md`**, **`FIREBASE_SECURITY.md`**, **`FIREBASE_SETUP.md`**. This file keeps collection and function field detail.

This document describes the Firebase-centric data layer for Mevora. It is the source of truth for collections, storage, rules, functions, retention, and client access. Product phases still follow `MEVORA_DEVELOPMENT.md`.

**Projects:** `mevora-dev` (development + emulators), `mevora-staging`, `mevora-production`. Never mix project data.

**Identity:** Firebase Authentication UID is the only primary key. Email, phone, and display name are attributes, never document IDs.

---

## 1. Services

| Service | Role |
| --- | --- |
| Authentication | Email, Google, Apple, Phone, Spotify (Spotify exchange is a Cloud Function) |
| Cloud Firestore | Account, profile, prefs, matches, chat, reports, devices |
| Cloud Storage | Profile photos and future chat images |
| Cloud Functions | Match creation, discovery feed, distance labels, FCM, deletion, retention |
| Cloud Messaging | Push for match / message / call. Clients never send FCM. |
| App Check | Play Integrity / **App Attest** in production; debug providers in development and staging |
| Analytics | Product events only. No phone, GPS, OTP, or message body. |
| Crashlytics | Enabled outside development |
| Remote Config | Product switches. **Not security.** Rules and functions stay authoritative. |
| Emulator Suite | Development Firestore/Functions/Storage; Auth emulator opt-in (`9099`) |

---

## 2. Collections

### `users/{uid}` — account only (private)

`uid`, `email`, `phoneNumber`, `phoneVerified`, `authProviders`, `createdAt`, `updatedAt`, `lastLoginAt`, `accountStatus`.

Other users cannot read this document. It is not a dating profile.

### `profiles/{uid}` — public dating projection

`displayName`, `birthDate` / `age`, `gender`, `bio`, `photos`, `interests`, `relationshipGoal`, `occupation`, `education`, `languages`, `city`, `profileCompleted`, `onboardingCompleted`, `isDiscoverable`, timestamps.

Never store password, phone, private email, GPS, FCM tokens, or auth providers here.

### `userPreferences/{uid}` (owner only)

`preferredGender`, `minAge`, `maxAge`, `maxDistance`, `relationshipGoals`, `interests`, `showMe`, `discoveryEnabled`.

### `userSettings/{uid}` (owner only)

`language`, `theme`, `notificationsEnabled`, `messageNotifications`, `matchNotifications`, `callNotifications`, `locationEnabled`, `showOnlineStatus`.

### `userPrivacy/{uid}` (owner only)

`showOnlineStatus`, `showDistance`, `showAge`, `allowNotifications`, `allowCalls`, `allowMessages`.

### `userLocation/{uid}` — owner read/write only

`latitude`, `longitude`, `geohash`, `updatedAt`.

Other clients never read this collection. The UI shows a derived label such as `"2 km away"` from `getDistanceLabel` / `getDiscoveryFeed`.

### `likes/{fromUid}_{toUid}`

Written only by `recordSwipe`. Clients cannot create likes or matches.

### `matches/{matchId}`

`matchId`, `userIds` (exactly two UIDs), `createdAt`, `updatedAt`, `isActive`, `lastMessage`, `lastMessageAt`. Participants only. Clients cannot create the document.

### `matches/{matchId}/messages/{messageId}`

`id`, `senderId`, `receiverId`, `type`, `text`, `createdAt`, `isRead`, `readAt`. Participants only. `senderId` must equal `request.auth.uid`.

Chat listeners attach only to the open conversation (`watchLatest`), not to every match.

### `notifications/{notificationId}`

Created by functions. Recipient can read and mark `isRead`.

### `reports/{reportId}`

Reporter can create and read their own reports. Admin review is later.

### `calls/{callId}`

Participants only. Temporary signaling; cleaned by retention.

### `users/{uid}/devices/{deviceId}` and `users/{uid}/fcmTokens/{tokenId}`

FCM tokens. Never public.

### Blocks

Preferred: `users/{uid}/blockedUsers/{blockedUserId}`. Legacy top-level `blocks/{blockerId}_{blockedUserId}` is still honored by functions. Blocked users cannot discover, message, call, or match.

### `purchases/{purchaseId}` — functions write only

Owner may read their own purchase ledger. Fields: `purchaseId`, `userId`, `productId`, `platform`, `transactionId`, `purchaseTokenHashOrReference` (hash), `status`, timestamps. No card or bank data. See `PAYMENT_ARCHITECTURE.md`.

### `users/{uid}/boosts/{boostId}` — functions write only

Owner may read. Other users cannot. Discovery ranking uses server-side active Boost (`expiresAt` vs now). Clients never write `status` / `expiresAt`.

---

## 3. Storage

| Path | Access |
| --- | --- |
| `users/{uid}/profile/pending/{imageId}` | Owner only until moderation |
| `users/{uid}/profile/{imageId}` | Authenticated read; owner write |
| `users/{uid}/profile/thumbs/{imageId}` | Discovery thumbnails |
| `users/{uid}/chat/{matchId}/{messageId}` | Owner write; match participants read |

Allowed types: `image/jpeg`, `image/jpg`, `image/png`, `image/webp`. Max 5 MB. The client compresses/resizes before upload (`ProfileImagePipeline`; max edge 1080, thumbs 320).

---

## 4. Auth

Firebase Auth is the session. `FirebaseUserDataSource` upserts the account document and a profile stub. `phoneVerified` is stored on the account document from a trusted phone sign-in, not guessed by other clients.

Banned / disabled accounts (`accountStatus`) cannot be flipped by the client.

---

## 5. Location, match, chat, notifications

- **Location:** GPS stays in `LocationService`. Persistence is `FirebaseLocationDataSource` → `userLocation/{uid}`. Distance for others is a callable.
- **Discovery:** `getDiscoveryFeed` paginates (default 10, max 20). The client does not query thousands of profiles or other users' coordinates.
- **Match:** `recordSwipe` in Cloud Functions verifies mutual likes. Client cannot write `likes` or create `matches`.
- **Chat:** One snapshot listener per open thread. Match list listens to match docs (preview fields), not every message.
- **Notifications:** Functions send FCM. Clients register device tokens only.

---

## 6. Cloud Functions

| Name | Purpose |
| --- | --- |
| `health` | Emulator probe; App Check off |
| `recordSwipe` | Like / pass / super-like + match creation |
| `unmatchUser` / `blockUser` / `reportUser` | Safety |
| `getDiscoveryFeed` | Paginated cards + distance label + compatibility + Boost ranking |
| `verifyBoostPurchase` | Store verification + Boost activation (never trust the client) |
| `activateBoost` | Activate from a verified purchase owned by the UID |
| `expireBoost` | Scheduled status=expired (Discovery still uses expiresAt) |
| `sendMatchNotification` / `sendMessageNotification` / `sendCallNotification` | FCM `newMatch`, `newMessage`, `incomingCall` / `missedCall` |
| `getDistanceLabel` | `"N km away"` without exposing coordinates |
| `deleteUserAccount` | Real deletion (see below) |
| `exportMyData` | GDPR / KVKK export shape |
| `spotifyCompleteAuth` | Server-side Spotify exchange (secret required) |
| `onProfilePhotoUploaded` | Moderation hook on pending photos |
| `retentionCleanup` | Scheduled (needs Blaze) |
| Video call callables | LiveKit tokens; gated by feature flags |

App Check is enforced on new callables when not running in the emulator.

---

## 7. Retention

`retentionCleanup` (daily stub) deletes:

- Notifications older than 30 days
- Ended call documents older than 30 days

Also planned: stale `userLocation` (no update for 30 days), unused FCM tokens, expired typing/presence. Scheduled functions require **Blaze**.

---

## 8. Account deletion

`deleteUserAccount` is not `isActive = false`. It:

1. Deletes Auth user
2. Deletes `users`, `profiles`, `userPreferences`, `userSettings`, `userPrivacy`, `userLocation`
3. Deletes devices / FCM tokens / blocked-user docs / likes / notifications
4. Deletes Storage prefix `users/{uid}/`
5. Deactivates matches, strips that user's name/photo, deletes messages (batch)

`exportMyData` returns account, profile, prefs, settings, privacy, and match ids (location only as `{present: bool}`).

---

## 9. Privacy and cost

- Public profile is a minimized projection.
- No extra global listeners. Discovery is paged. Swipes do not re-query the whole database.
- Indexes live in `firebase/firestore.indexes.json`.
- Firestore persistence is on; `FirestoreSessionCache` clears it on logout when no listeners are active.

---

## 10. Analytics

Allowed: `app_open`, `sign_up`, `login`, `profile_completed`, `like`, `match`, `message`, `video_call` (plus existing swipe/report events).

Forbidden parameters: phone, GPS, message body, OTP.

---

## 11. Remote Config (not security)

| Key | Default |
| --- | --- |
| `minimumAge` | 18 |
| `maxDiscoveryDistance` | 100 |
| `maxDailyLikes` | 100 |
| `videoCallEnabled` | false |
| `premiumEnabled` | false |
| `maintenanceMode` | false |

Daily like caps and maintenance UX can use these values. Enforcement of likes, blocks, and matches stays in Functions + rules.

---

## 12. Flutter data layer

Firebase SDKs are imported only in `*DataSource` classes:

- `FirebaseUserDataSource`
- `FirebaseProfileDataSource`
- `FirebaseMatchDataSource`
- `FirebaseChatDataSource`
- `FirebaseStorageDataSource`
- `FirebaseNotificationDataSource`
- `FirebaseMessagingDataSource`
- `FirebaseLocationDataSource`

Repositories (`ProfileRepository`, `MatchRepository`, `ChatRepository`, `LocationRepository`, `StorageRepository`) depend on those datasources. Domain entities and use cases do not import `cloud_firestore` or `firebase_auth`.

Development uses Firestore / Functions / Storage emulators via `AppConfig.useEmulators`. Auth emulator is opt-in (`useAuthEmulator`) so Phone Auth can send real SMS.
