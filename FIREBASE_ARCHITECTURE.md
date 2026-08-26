# Firebase architecture

Mevora uses the **existing** Firebase projects already configured in this repo. This file is the architecture view. Setup steps: `FIREBASE_SETUP.md`. Security: `FIREBASE_SECURITY.md`. Collection field details: `FIREBASE_DATA_ARCHITECTURE.md`. Connection / flavors: `FIREBASE_CONNECTION.md`.

**No new Firebase or GCP project is created by the app or by agents.** `firebase_options` values must not be regenerated or overwritten.

## Source of truth (project IDs)

There is no generated `lib/firebase_options.dart`. Flavor options live in `lib/core/config/firebase/firebase_options_resolver.dart` and match native configs:

| Environment | Flavor | projectId | Android applicationId | iOS bundle ID |
| --- | --- | --- | --- | --- |
| Development | `development` | `mevora-dev` | `com.mevora.app.dev` | `com.mevora.app.dev` |
| Staging | `staging` | `mevora-staging` | `com.mevora.app.staging` | `com.mevora.app.staging` |
| Production | `production` | `mevora-production` | `com.mevora.app` | `com.mevora.app` |

`FirebaseOptionsResolver.resolve(environment)` is the flavor equivalent of `DefaultFirebaseOptions.currentPlatform`.

CLI: `npx.cmd firebase use mevora-dev` (or `mevora-staging` / `mevora-production`). Never guess a new ID. A leftover Console project such as `mevora-d6ed0` is **not** used by the Flutter app.

## Init path

1. Entrypoint (`lib/main.dart` or `lib/main_{development,staging,production}.dart`) calls `bootstrap(environment)`.
2. `WidgetsFlutterBinding.ensureInitialized()`.
3. `FirebaseBootstrap.initialize` → `Firebase.initializeApp(options: FirebaseOptionsResolver.resolve(...))` **before** Auth, Firestore, Storage, Messaging, Crashlytics, Analytics, or App Check.
4. Development connects to the Emulator Suite. Staging/production talk to the matching project.
5. On failure, `MevoraStartupErrorApp` is shown (localized, **no raw Firebase errors**). Feature code does not start.
6. `runApp(MevoraApp(...))`.

Identity is the Firebase Auth **UID** only. Email is never an admin allowlist.

## Console services already assumed active

These products are already enabled on the existing projects (do not recreate them):

- Authentication (including Phone)
- Cloud Firestore
- Cloud Storage
- Cloud Messaging
- App Hosting (web/backend only — see below)
- Analytics / Crashlytics (collection off in development)

## App Hosting

Firebase App Hosting on these projects is for **web and backend** (the Console web app on `mevora-dev`, Cloud Functions, future admin/web). It does **not** run the Flutter mobile app. iOS and Android still ship through App Store and Google Play with `--flavor`.

## Data layer (Firebase only in DataSources)

UI, domain, and controllers must not call `FirebaseAuth.instance`, `FirebaseFirestore.instance`, `FirebaseStorage.instance`, or `FirebaseMessaging.instance`.

| Role | Implementation |
| --- | --- |
| Auth | `FirebaseAuthDataSource` (phone OTP) plus email / Google / Apple / Spotify services in `features/authentication/data/services/` |
| Account Firestore | `FirebaseUserDataSource` (`users/{uid}`) |
| Profile / prefs / privacy | `FirebaseProfileDataSource`, `FirebaseSettingsDataSource` |
| Location | `FirebaseLocationDataSource` (`userLocation/{uid}`, owner-only) |
| Matches / likes | `FirebaseMatchDataSource` / `FirebaseMatchRepository` (swipes via Functions) |
| Chat | `FirebaseChatDataSource` (active conversation listener only) |
| Storage | `FirebaseStorageDataSource` (`users/{uid}/profile/…`, compress before upload) |
| Messaging | `FirebaseMessagingDataSource` (`users/{uid}/devices/{deviceId}`) |
| Purchases / Boost | `FirebasePurchaseDataSource` (read-only; writes are Functions) |

Split Firestore sources are intentional. There is no god `FirebaseFirestoreDataSource`.

Phone OTP is **Firebase Auth only**. The app never generates, stores, or logs OTP codes.

Spotify sign-in uses a **custom token** from `spotifyCompleteAuth`.

## Collections

`users`, `profiles`, `userSettings`, `userPreferences`, `userPrivacy`, `userLocation`, `matches` / `messages`, `calls`, `notifications`, `devices` (under `users/{uid}`), `purchases`, `users/{uid}/boosts`, `users/{uid}/boostWallet`, `boostProducts`.

Passwords never go to Firestore. Exact lat/lng are owner-only. Chat: participants only; `senderId == request.auth.uid`. Clients cannot set `boost.status` or `boost.expiresAt`.

Video: Firestore holds **signaling / state / history** only. Media is not streamed through Firestore.

## Cloud Functions (europe-west1)

| Export | Role |
| --- | --- |
| `verifyBoostPurchase` | IAP verification + wallet credit |
| `activateBoost` | Consume 1 Boost from the signed-in UID's wallet |
| `expireBoost` | Scheduled; sets `status=expired` |
| `sendMatchNotification` | Trigger on `matches/{id}` → FCM `newMatch` |
| `sendMessageNotification` | Trigger on messages → FCM `newMessage` + match preview |
| `sendCallNotification` | Trigger on `calls/{id}` → `incomingCall` / `missedCall` |
| `recordSwipe`, `getDiscoveryFeed`, `getDistanceLabel`, `deleteUserAccount`, `spotifyCompleteAuth`, video callables | Dating / safety / account |

FCM types: `newMatch`, `newMessage`, `incomingCall`, `missedCall`, `boostActivated`, `boostExpired`.

## Cost

- No all-users client fetch. Discovery is a paged callable.
- No GPS write spam (`LocationUpdatePolicy`).
- Chat snapshot listener only for the open conversation.
- Indexes: `firebase/firestore.indexes.json` (discovery profiles, matches, messages, notifications).
