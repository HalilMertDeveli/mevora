# Mevora Firestore Security

Canonical security summary: **`FIREBASE_SECURITY.md`**. Rules live in `firebase/firestore.rules` and `firebase/storage.rules`. They are prototype-complete but ownership-enforced. **Never** `allow read, write: if true;`.

Identity is `request.auth.uid`. Clients cannot spoof another user's `uid`.

---

## Helper functions

| Function | Meaning |
| --- | --- |
| `isAuthenticated()` | `request.auth != null` |
| `isOwner(userId)` | Signed-in user is that UID |
| `isMatchParticipant(matchId)` | UID is in `matches/{id}.userIds` |
| `isBlockedPair(a, b)` | Either user has a `blockedUsers` doc for the other |
| `unchanged(key)` | Field cannot be rewritten to a new value |

Unauthenticated access is denied everywhere. Unknown collections fall through to `allow read, write: if false`.

---

## `users/{userId}`

| Action | Who | Notes |
| --- | --- | --- |
| read | owner | Account is private. No other client reads email, phone, or providers. |
| create | owner | `id` or `uid` must equal `userId`. Cannot create banned. |
| update | owner | Cannot change `isBanned`, `isVerified`, or `accountStatus`. Cannot spoof uid. |
| delete | none | Account deletion is `deleteUserAccount`. |

### `users/{userId}/devices/{deviceId}`

| Action | Who |
| --- | --- |
| read / delete | owner |
| create / update | owner, `token` string ≤ 4096 |

FCM tokens are never public.

### `users/{userId}/fcmTokens/{tokenId}`

Owner read/write (legacy path still used by FCM send).

### `users/{userId}/blockedUsers/{blockedUserId}`

| Action | Who |
| --- | --- |
| get | owner, or the blocked user (so rules can see a block) |
| list | owner only |
| write | owner, and not self-block |

### `users/{userId}/presence/current`

Write: owner. Read: owner, or others only when `userPrivacy/{id}.showOnlineStatus == true`.

---

## `profiles/{userId}`

| Action | Who | Notes |
| --- | --- | --- |
| read | any authenticated user | Public dating card only |
| create / update | owner | `uid` must match (or default to path id). Size limits on name/bio/photos. Forbidden keys: `email`, `phoneNumber`, `password`, `authProviders`, `latitude`, `longitude`, `geohash`, `fcmToken`, `token` |
| delete | none | |

---

## `userPreferences/{userId}`

| Action | Who | Notes |
| --- | --- | --- |
| read | owner | |
| write | owner | `minAge >= 18`, `maxAge >= minAge`, `maxDistance` in 1..500 |

---

## `userSettings/{userId}` / `userPrivacy/{userId}`

Read and write: owner only.

---

## `userLocation/{userId}`

| Action | Who | Notes |
| --- | --- | --- |
| read | **owner only** | Other clients never receive lat/lng |
| create / update | owner | Valid lat/lng and geohash |
| delete | owner | |

Distance UI must call `getDistanceLabel` or `getDiscoveryFeed`.

---

## `likes/{likeId}`

| Action | Who |
| --- | --- |
| read | actor (`fromUserId == auth.uid`) |
| write | **none** (Cloud Function `recordSwipe`) |

---

## `matches/{matchId}`

| Action | Who | Notes |
| --- | --- | --- |
| read | participants | |
| create / delete | **none** | Created only after mutual likes |
| update | participants | Cannot change `userIds` / `createdAt`. Allowed: `lastMessage`, `lastMessageAt`, `isActive`, unmatch fields, unread / isNew maps |

### `matches/{matchId}/messages/{messageId}`

| Action | Who | Notes |
| --- | --- | --- |
| read | participants | |
| create | participants | Match must be active. `senderId == auth.uid`. Receiver is the other participant. Not blocked. Text ≤ 2000. |
| update | participants | `isRead`, `readAt`, `status` only. Cannot change sender/receiver. |
| delete | none | Retention is a backend job |

---

## `notifications/{notificationId}`

| Action | Who |
| --- | --- |
| read | `userId == auth.uid` |
| create / delete | none (functions) |
| update | recipient, `isRead` / `readAt` only |

---

## `reports/{reportId}`

| Action | Who |
| --- | --- |
| read | reporter (`reporterId == auth.uid`) |
| create | authenticated, `reporterId == auth.uid`, not self |
| update / delete | none (admin later) |

---

## `calls/{callId}` / `callHistory/{historyId}`

Calls: participants may **read**. Create/update/delete are Functions only (signaling/state/history, not media). History is read-only for participants.

---

## `blocks/{blockId}` (legacy)

Create/delete by `blockerId == auth.uid`. Read by either party. Preferred path is `users/{uid}/blockedUsers/{id}`.

---

## `purchases/{purchaseId}` / `users/{userId}/boosts/{boostId}`

| Action | Who |
| --- | --- |
| read | owner only (`userId == auth.uid`) |
| write | **none** (Cloud Function `verifyBoostPurchase`) |

Other users cannot read purchases or boosts. Clients cannot set `status`, `expiresAt`, `verifiedAt`, `purchaseId`, or `transactionId`.

---

## Cloud Storage

| Path | read | write |
| --- | --- | --- |
| `users/{uid}/profile/pending/{imageId}` | owner | owner, image jpeg/png/webp, < 5 MB |
| `users/{uid}/profile/{imageId}` | authenticated | owner, same type/size |
| `users/{uid}/profile/thumbs/{imageId}` | authenticated | owner |
| `users/{uid}/chat/{matchId}/{messageId}` | owner or match participant | owner |
| everything else | denied | denied |

---

## What the client must not do

- Create `matches` or `likes`
- Send FCM
- Read another user's `userLocation`, account email/phone, or device tokens
- Mark their own photos as moderation-approved as a security control (functions own publish)
- Treat Remote Config as authorization
