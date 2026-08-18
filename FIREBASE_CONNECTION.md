# Firebase connection

Canonical docs: **`FIREBASE_ARCHITECTURE.md`**, **`FIREBASE_SECURITY.md`**, **`FIREBASE_SETUP.md`**. Collection details: `FIREBASE_DATA_ARCHITECTURE.md`.

Mevora uses the **existing** Firebase projects. No new GCP/Firebase project was created, and `lib/firebase_options.dart` was not generated or overwritten.

## Projects

| Environment | Flavor | Firebase project ID | Android applicationId | iOS bundle ID |
| --- | --- | --- | --- | --- |
| Development | `development` | `mevora-dev` | `com.mevora.app.dev` | `com.mevora.app.dev` |
| Staging | `staging` | `mevora-staging` | `com.mevora.app.staging` | `com.mevora.app.staging` |
| Production | `production` | `mevora-production` | `com.mevora.app` | `com.mevora.app` |

## Options file used per environment

There is **no** generated `DefaultFirebaseOptions` file. FlutterFire options live in:

`lib/core/config/firebase/firebase_options_resolver.dart`

`FirebaseOptionsResolver.resolve(environment)` is the flavor equivalent of `DefaultFirebaseOptions.currentPlatform`. Values match:

- `android/app/src/{flavor}/google-services.json`
- `ios/flavors/{flavor}/GoogleService-Info.plist`

Do not copy API keys or project IDs into other Dart files. Do not run FlutterFire `configure` in a way that overwrites these configs.

## Init path

1. Entrypoint (`lib/main.dart`, `lib/main_development.dart`, `lib/main_staging.dart`, `lib/main_production.dart`) calls `bootstrap(environment)`.
2. `lib/bootstrap.dart` runs `WidgetsFlutterBinding.ensureInitialized()`.
3. `FirebaseBootstrap.initialize` in `lib/core/services/firebase/firebase_bootstrap.dart` calls `Firebase.initializeApp(options: FirebaseOptionsResolver.resolve(...))`.
4. Only after that: Auth, Firestore, Storage, Messaging, Crashlytics, Analytics, App Check, and `runApp`.
5. If initialization fails, the app shows `MevoraStartupErrorApp` (user-safe copy, no raw Firebase errors) and does not start feature code.

Identity is the Firebase Auth UID. Admin access is not decided by email on the client.

## How to run

Always pass a flavor so Android `applicationId` / iOS bundle ID match the Firebase apps.

```bash
npx.cmd -y firebase-tools@latest emulators:start --project mevora-dev
flutter run --flavor development -t lib/main_development.dart
```

```bash
flutter run --flavor staging -t lib/main_staging.dart
flutter run --flavor production -t lib/main_production.dart
```

Development (`AppConfig.useEmulators`) talks to the Emulator Suite for Firestore `8080`, Functions `5001`, and Storage `9199`. **Auth emulator is off by default** so Firebase Phone Auth can send real SMS via `mevora-dev`. Opt in with `--dart-define=USE_AUTH_EMULATOR=true` (Auth `9099`, no SMS). Android emulator host is `10.0.2.2`; iOS/desktop host is `127.0.0.1`; override with `FIREBASE_EMULATOR_HOST`. Physical devices should pass `--dart-define=USE_EMULATORS=false`.

VS Code / Cursor launches are in `.vscode/launch.json`.

## Native config check

Android flavor `google-services.json` package names match Gradle `applicationId` (`com.mevora.app` + `.dev` / `.staging`).

iOS flavor plists match `FirebaseOptionsResolver` bundle IDs. Xcode schemes `development`, `staging`, and `production` set `PRODUCT_BUNDLE_IDENTIFIER` to the same values. A build-phase script copies `ios/flavors/{flavor}/GoogleService-Info.plist` into `ios/Runner/`.

**Mismatch if you skip `--flavor`:** the leftover `Runner` scheme still uses bundle `com.mevora.app`, while the committed `ios/Runner/GoogleService-Info.plist` is the development (`com.mevora.app.dev` / `mevora-dev`) file. Always run with a flavor.

## Remaining Console steps (you configure these)

Do these in each existing project (`mevora-dev`, `mevora-staging`, `mevora-production`) as needed. Do not create new apps or projects.

- **Authentication:** Email/password, Google, Apple, Phone. SHA-1/SHA-256 for Android Google Sign-In. Apple Services ID / redirect for Android Apple Sign-In.
- **Storage:** Enable and deploy `firebase/storage.rules`.
- **Cloud Messaging:** APNs key/certs in the iOS app; Android notifications permission as required by Play policy.
- **App Check:** Play Integrity / **App Attest** in production. Register debug tokens locally (development/staging) — do not commit production App Check credentials.
- **Crashlytics / Analytics:** Confirm collection in the Console after a staging/production run.
- **Cloud Functions:** Deploy including `verifyBoostPurchase`, `activateBoost`, `expireBoost`, `sendMatchNotification`, `sendMessageNotification`, `sendCallNotification` (server-authoritative; the client never writes boost status).
- **App Hosting:** Web/backend only. The Flutter mobile app is not served from App Hosting.
- **Play / App Store:** Store listing, signing, in-app products for Boost, privacy questionnaires.

Google Sign-In OAuth brand support email lives in Firebase Console / `firebase.json`. It is not an in-app admin allowlist.
