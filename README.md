# Mevora

> Mevora, yakındaki insanları değil **uyumlu bağlantıları** keşfetmen için tasarlanmış bir dating uygulamasıdır.

Mevora is a dating app for iOS and Android that helps people find connections they are likely to click with — not simply people nearby. Compatibility, shared interests, and relationship goals sit at the center of discovery. The product has its own brand, UX, matching engine, and codebase; it is not a clone of Tinder or any other app.

**Package ID:** `com.mevora.app`  
**Platforms:** iOS + Android · Flutter · Firebase  
**Status:** Private / proprietary

---

## Highlights

- **Auth** — Google, Apple, Spotify, and phone sign-in
- **Location** — used for matching and distance; **exact GPS is never shown to other users**
- **Discovery + compatibility** — swipe-based discovery with a dedicated compatibility engine (score, shared interests, goals, lifestyle)
- **Matches** — Like / Pass / Super Like; a match is created when both people like each other
- **Chat** — messaging between matched users
- **1:1 video** — LiveKit-ready call path (feature-flagged; media SDK is swappable)
- **Boost IAP only** — a one-time consumable that boosts Discovery visibility. No subscriptions, no coin wallet
- **Localization** — Turkish (`tr`) and English (`en`)

---

## Architecture

Feature-first layout with Clean Architecture: presentation → controller / use case → domain repository → data (Firebase / device SDKs). Features communicate through domain types and repository interfaces, not each other’s internals.

See **[ARCHITECTURE.md](ARCHITECTURE.md)** for dependency rules, DI (`InheritedWidget` scopes), and folder layout.

---

## Environments

| Flavor | Dart entrypoint | Application ID | Firebase project |
| --- | --- | --- | --- |
| development | `lib/main_development.dart` | `com.mevora.app.dev` | `mevora-dev` |
| staging | `lib/main_staging.dart` | `com.mevora.app.staging` | `mevora-staging` |
| production | `lib/main_production.dart` | `com.mevora.app` | `mevora-production` |

Development talks to the Emulator Suite for **Firestore / Functions / Storage**. Phone Auth uses **live `mevora-dev`** by default because the Auth emulator cannot send SMS. Pass `--dart-define=USE_AUTH_EMULATOR=true` only for local test numbers.

---

## How to run

```bash
flutter pub get
npx.cmd -y firebase-tools@latest emulators:start --only firestore --project mevora-dev
flutter run --flavor development -t lib/main_development.dart
```

Real SMS on a **physical device** (recommended). `10.0.2.2` is only reachable from the Android emulator:

```bash
flutter run --flavor development -t lib/main_development.dart --dart-define=USE_EMULATORS=false
```

Auth emulator (no SMS; Console/emulator test numbers only):

```bash
npx.cmd -y firebase-tools@latest emulators:start --only auth,firestore --project mevora-dev
flutter run --flavor development -t lib/main_development.dart --dart-define=USE_AUTH_EMULATOR=true
```

Other flavors:

```bash
flutter run --flavor staging -t lib/main_staging.dart
flutter run --flavor production -t lib/main_production.dart
```

Checks:

```bash
flutter analyze
flutter test
```

Development order and phase gates live in [MEVORA_DEVELOPMENT.md](MEVORA_DEVELOPMENT.md). Do not skip phases.

---

## Documentation

| Topic | Document |
| --- | --- |
| Product phases & principles | [MEVORA_DEVELOPMENT.md](MEVORA_DEVELOPMENT.md) |
| App architecture | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Firebase architecture | [FIREBASE_ARCHITECTURE.md](FIREBASE_ARCHITECTURE.md) |
| Firebase setup | [FIREBASE_SETUP.md](FIREBASE_SETUP.md) |
| Firebase connection | [FIREBASE_CONNECTION.md](FIREBASE_CONNECTION.md) |
| Firestore data model | [FIREBASE_DATA_ARCHITECTURE.md](FIREBASE_DATA_ARCHITECTURE.md) |
| Firebase security | [FIREBASE_SECURITY.md](FIREBASE_SECURITY.md) |
| Firestore rules | [FIRESTORE_SECURITY.md](FIRESTORE_SECURITY.md) |
| Phone auth | [PHONE_AUTH_IMPLEMENTATION.md](PHONE_AUTH_IMPLEMENTATION.md) |
| Location & privacy | [LOCATION_ARCHITECTURE.md](LOCATION_ARCHITECTURE.md) |
| Boost / IAP | [PAYMENT_ARCHITECTURE.md](PAYMENT_ARCHITECTURE.md) |
| TR / EN localization | [LOCALIZATION_ARCHITECTURE.md](LOCALIZATION_ARCHITECTURE.md) |

---

## Secrets and store consoles

App Store / Play products, OAuth SHA fingerprints, LiveKit secrets, Spotify client secret, Apple IAP private keys, and service accounts are configured by the owner in the respective consoles. **They do not belong in this repository.**

Public client IDs may be passed at build time (for example `--dart-define=SPOTIFY_CLIENT_ID=`). Never commit `.env`, `*.jks`, `key.properties`, or service-account JSON.

---

## License

Private and proprietary. All rights reserved.
