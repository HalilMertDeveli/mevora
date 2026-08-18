# Firebase setup

Mevora is already wired to **existing** Firebase projects. Do **not** create a new Firebase/GCP project. Do **not** run FlutterFire configure in a way that overwrites `firebase_options_resolver.dart`, `google-services.json`, or `GoogleService-Info.plist`.

Architecture: `FIREBASE_ARCHITECTURE.md`. Security: `FIREBASE_SECURITY.md`. Flavors: `FIREBASE_CONNECTION.md`.

## Projects already in this repo

| Flavor | projectId | Native config |
| --- | --- | --- |
| development | `mevora-dev` | `android/app/src/development/google-services.json`, `ios/flavors/development/GoogleService-Info.plist` |
| staging | `mevora-staging` | `android/app/src/staging/â€¦`, `ios/flavors/staging/â€¦` |
| production | `mevora-production` | `android/app/src/production/â€¦`, `ios/flavors/production/â€¦` |

On Windows:

```bash
npx.cmd -y firebase-tools@latest use mevora-dev
npx.cmd -y firebase-tools@latest emulators:start --project mevora-dev
flutter run --flavor development -t lib/main_development.dart
```

`firebase use` must be one of the three IDs above â€” never a newly created project.

## Already assumed enabled in Console

Do not recreate these; they are already on for Mevora:

- Authentication
- Phone verification
- Cloud Firestore
- Cloud Storage
- Cloud Messaging
- App Hosting (web/backend only)
- Analytics

## App Hosting (web/backend only)

App Hosting is **not** how the Flutter iOS/Android app is released. Mobile still goes to Play Store and App Store with flavors. Use App Hosting for web/admin/backend on the same existing projects (the `mevora-dev` web app is already registered). Do not host the mobile Flutter binary there.

## Remaining Console steps (you do these)

Repeat per existing project (`mevora-dev`, `mevora-staging`, `mevora-production`) as needed.

### Authentication â€” Google

1. Enable Google sign-in.
2. Add Android SHA-1 and SHA-256 for each flavor package (`com.mevora.app`, `.dev`, `.staging`).
3. Create a **Web** OAuth client if Android id-token sign-in needs `GOOGLE_WEB_CLIENT_ID` (`--dart-define`).
4. `google-services.json` currently has empty `oauth_client` arrays until SHA fingerprints are added â€” then download is optional; do not overwrite project IDs.

### Authentication â€” Apple

1. Enable Apple provider.
2. Apple Developer: Services ID, redirect URL `https://<projectId>.firebaseapp.com/__/auth/handler`.
3. Pass `APPLE_SERVICE_ID` / `APPLE_REDIRECT_URI` if Android Apple sign-in is used.

### Authentication â€” Phone

1. Enable Phone provider in Console (MCP cannot enable it). Required on `mevora-dev` before any real SMS.
2. Upgrade the project to **Blaze**. Spark cannot send SMS to real numbers.
3. SMS region policy must allow TR (set on `mevora-dev` for the in-app country catalog). Repeat for staging/production.
4. Add test phone numbers only in Console. The app never invents OTP codes.

### App Check

1. Development/staging: register debug tokens from the device log.
2. Production Android: Play Integrity.
3. Production iOS: **App Attest**.
4. Enforce App Check on Functions (already `enforceAppCheck` when not emulating).

### Cloud Messaging

1. Upload an APNs key/cert on the iOS apps.
2. Android: notification permission as required by Play policy.
3. Tokens are stored at `users/{uid}/devices/{deviceId}`.

### Cloud Functions

Deploy from the repo (Blaze required for scheduled `expireBoost` / `retentionCleanup`):

```bash
npx.cmd -y firebase-tools@latest deploy --only functions,firestore:rules,firestore:indexes,storage --project mevora-dev
```

Include `verifyBoostPurchase`, `activateBoost`, `expireBoost`, `sendMatchNotification`, `sendMessageNotification`, `sendCallNotification`. Store IAP verification secrets (Play / App Store) as Function params/secrets â€” never in the Flutter app.

### Firestore / Storage rules

Deploy `firebase/firestore.rules`, `firebase/firestore.indexes.json`, `firebase/storage.rules`. Confirm Storage is enabled on each project.

### App Hosting / Hosting

Configure only if you ship a **web** backend or admin UI on these projects. Skip for the Flutter mobile binary.

### Stores

Play / App Store listing, signing, Boost IAP products, privacy questionnaires. SHA keys and APNs are Console/store work, not Dart.

## Emulators (development)

`AppConfig.useEmulators` is true only in development: Firestore `8080`, Functions `5001`, Storage `9199`. Auth emulator (`9099`) is opt-in (`USE_AUTH_EMULATOR=true`) because it cannot send SMS. Android emulator host `10.0.2.2`; iOS/desktop host `127.0.0.1`.
