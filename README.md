# Mevora

**Mevora** is a Flutter dating and social discovery app for iOS and Android. It helps people find connections they are likely to click with — through shared interests, music taste, relationship views, and a dedicated compatibility engine — not simply whoever happens to be nearby.

| | |
| --- | --- |
| **Package** | `com.mevora.app` |
| **Platforms** | iOS · Android |
| **Stack** | Flutter · Firebase · Cloud Functions · LiveKit (video) |
| **Locales** | Turkish (`tr`) · English (`en`) |
| **Status** | Private / proprietary |

<p align="center">
  <img src="docs/images/login-hero.jpg" alt="Mevora login hero" width="720" />
</p>

<p align="center">
  <img src="docs/images/portrait-01.jpg" alt="Discovery portrait sample" width="140" />
  <img src="docs/images/portrait-02.jpg" alt="Discovery portrait sample" width="140" />
  <img src="docs/images/portrait-03.jpg" alt="Discovery portrait sample" width="140" />
  <img src="docs/images/portrait-04.jpg" alt="Discovery portrait sample" width="140" />
  <img src="docs/images/portrait-05.jpg" alt="Discovery portrait sample" width="140" />
</p>

> Visuals above are **project assets** used by the app (login hero and discovery mock portraits). Full UI screenshots are not checked into this repository yet.

---

## Table of contents

- [Highlights](#highlights)
- [Product features](#product-features)
- [Architecture](#architecture)
- [Project structure](#project-structure)
- [Firebase & backend](#firebase--backend)
- [Environments](#environments)
- [Getting started](#getting-started)
- [Testing](#testing)
- [Localization](#localization)
- [Animations (Rive)](#animations-rive)
- [Security & privacy](#security--privacy)
- [Documentation map](#documentation-map)
- [Secrets](#secrets)
- [License](#license)

---

## Highlights

- **Multi-provider auth** — email/password, Google, Apple, phone OTP, and Spotify (OAuth + custom token)
- **Discovery with compatibility** — swipe feed (Like / Pass / Super Like) scored by a pluggable compatibility engine
- **Music match** — Spotify taste sync, same-taste profiles, weekly music stats
- **Relationship match** — timed relationship Q&A prompts and view-based compatibility suggestions
- **Match Score** — server-side score seeding, match bonuses, and post-match feedback
- **Chat** — text, photo, GIF, and voice messages between matched users
- **1:1 video** — signaling via Cloud Functions; media through LiveKit (feature-flagged) with a mock provider for demos
- **Boost IAP** — consumable boost packs only (no subscriptions in production path)
- **Location-aware ranking** — distance labels from the backend; **exact GPS is never exposed to other clients**
- **TR / EN** localization via Flutter gen-l10n
- **Compact Rive motion** — loading, empty, match celebration, and micro page accents (never full-screen blockers)

---

## Product features

### Authentication

| Method | Notes |
| --- | --- |
| Email / password | Register, sign-in, password reset |
| Google Sign-In | `google_sign_in` + Firebase Auth |
| Sign in with Apple | Native Apple credential flow |
| Phone OTP | Firebase Phone Auth (+ SMS); screens under `/phone` |
| Spotify | OAuth deep link → Cloud Function `spotifyCompleteAuth` → custom Firebase token. Gated by `FeatureFlags.spotifyLoginEnabled` (default off until configured). |

Composition lives in `lib/features/authentication/data/auth_composition.dart`.

### Onboarding & profile

Multi-step onboarding (basics, interests, education, relationship goal, lifestyle, bio, photos). Profile photos upload through Firebase Storage. Settings cover edit profile, discovery preferences, privacy, blocked users, notifications, language, and account controls.

### Discovery & matching

- Card stack with swipe gestures and action buttons
- Filters (age, distance, relationship goal, and related preferences)
- Mutual likes create a match (server-authoritative `recordSwipe`)
- Match celebration UI with compact Rive accent
- Bottom shell tabs: **Discovery · Matches · Music · Profile**

### Match Score

Feature module `lib/features/match_score/` with Cloud Functions for seeding on user create, awarding bonuses on match, and collecting / dismissing feedback prompts.

### Music Match

- Link Spotify account and sync taste
- Same-taste discovery list
- Weekly music stats UI
- Client talks to Functions (`spotifyLinkMusic`, sync / disconnect helpers); music compatibility helpers also feed discovery ranking on the backend

### Relationship Match

- Periodic in-app relationship questions (`RelationshipPromptHost`)
- Answers stored via `saveRelationshipAnswer`
- Suggestions via `getRelationshipMatches`
- Compatibility badges on discovery profile details when scores exist

### Chat

| Type | Support |
| --- | --- |
| Text | Yes |
| Image / photo | Yes (Storage-backed) |
| GIF | Message type present |
| Voice | Record + playback (`record`, `audioplayers`) |
| Presence / typing | Yes |

Unmatch, block, and report flows hang off chat / safety UI.

### Video calls

- Domain state machine + `VideoCallProvider` abstraction
- **LiveKit** provider for Firebase-backed social graph
- **Mock** provider for in-memory / demo graphs
- Cloud Functions: `createVideoCall`, `respondToVideoCall`, `endVideoCall`, `expireVideoCall`
- Gated by `FeatureFlags.videoCallsEnabled` (default **off** until configured)

### Boost (payments)

Consumable in-app purchases only (`in_app_purchase`):

- Packs such as `com.mevora.app.boost.1` / `.5` / `.10`
- Server verification: `verifyBoostPurchase`, `activateBoost`, `expireBoost`
- Temporary Discovery visibility boost (owner-only documents)

Subscriptions exist only as a **disabled placeholder** (`DisabledSubscriptionRepository`) — not a live product path.

### Location

Permission + capture via `geolocator` / `permission_handler`. Coarse location is written for ranking; clients receive **distance labels** from Functions, not raw coordinates of other users.

### Safety & notifications

- Report / block
- FCM push routing (`firebase_messaging`)
- Crashlytics + Analytics + App Check wired in bootstrap

---

## Architecture

Mevora uses **feature-first Clean Architecture** with a single DI style: constructor injection + `InheritedWidget` scopes. There is **no** Riverpod, Bloc, or GetIt.

```text
UI (widgets / pages)
        ↓
Controller (ChangeNotifier)
        ↓
Use case (only when logic is non-trivial)
        ↓
Repository interface (domain)
        ↓
Repository implementation (data)
        ↓
Firebase · device SDKs · Cloud Functions · LiveKit
```

### Layers

| Layer | Owns | Must not own |
| --- | --- | --- |
| **Presentation** | Widgets, controllers, navigation, l10n-facing copy | Firebase types, Firestore |
| **Domain** | Entities, policies, repository contracts | Flutter UI widgets, Firebase SDKs |
| **Data** | Firebase/SDK adapters, DTOs, mappers → `AppException` / `Failure` | Widget trees |
| **Core** | Config, routing, theme, errors, DI scopes, shared ports | Feature internals (except composition roots) |

### Dependency rules

1. `presentation` → `domain` (+ `core`, `shared`)
2. `domain` → `core` only
3. `data` → `domain` + SDKs
4. Features talk through **domain types / repository interfaces**, never another feature’s `data/` or private widgets

### State & DI

- Controllers: `AuthController`, `DiscoveryController`, `ChatController`, `CallController`, `MusicController`, `RelationshipController`, …
- Scopes: `AuthScope`, `SocialScope`, `DiscoveryScope`, `BoostScope`, `MusicScope`, `MatchScoreScope`, `RelationshipScope`, `LocationScope`, …
- Routing: **`go_router`** with `StatefulShellRoute` for the four main tabs

See **[ARCHITECTURE.md](ARCHITECTURE.md)** for SOLID notes, error mapping, and testing fakes.

---

## Project structure

```text
Mevora/
├── android/ · ios/          Native hosts + flavors
├── assets/
│   ├── images/              Login hero, discovery mock portraits
│   ├── fonts/               Fraunces · Manrope
│   └── rive/                Feature-scoped .riv files
├── docs/images/             README visuals (copied from app assets)
├── firebase/                Firestore & Storage security rules, indexes
├── functions/               Node Cloud Functions (TypeScript)
├── lib/
│   ├── core/                Config, DI, routing, theme, Firebase bootstrap
│   ├── features/
│   │   ├── authentication/
│   │   ├── onboarding/
│   │   ├── profile/
│   │   ├── location/
│   │   ├── discovery/
│   │   ├── matching/
│   │   ├── match_score/
│   │   ├── music/
│   │   ├── relationship/
│   │   ├── chat/
│   │   ├── calls/           LiveKit + mock video
│   │   ├── boost/
│   │   ├── notifications/
│   │   ├── permissions/
│   │   ├── safety/
│   │   ├── settings/
│   │   ├── subscription/    Disabled placeholder
│   │   └── video/           Legacy disabled adapter stub
│   ├── shared/              Design system, Rive wrappers, images
│   ├── l10n/                ARB + generated localizations
│   ├── main_development.dart
│   ├── main_staging.dart
│   └── main_production.dart
└── test/                    Unit + widget + rules contract tests
```

Each feature typically follows:

```text
features/<name>/
  data/          datasources · repositories · services
  domain/        entities · repositories · policies · usecases
  presentation/  pages · widgets · controllers
```

---

## Firebase & backend

### Client SDKs (wired)

| Product | Role |
| --- | --- |
| Authentication | All identity providers |
| Cloud Firestore | Profiles, matches, chat, social graph |
| Cloud Storage | Profile & chat media |
| Cloud Functions | Discovery, swipes, Spotify, boost, calls, relationship, match score |
| Cloud Messaging | Push |
| Crashlytics | Crash reporting |
| Analytics | Product analytics |
| App Check | Debug / Play Integrity / App Attest by environment |

### Notable callable / trigger areas

| Area | Examples |
| --- | --- |
| Discovery | `getDiscoveryCandidates`, `getDiscoveryFeed`, `recordDiscoveryDecision`, `getDistanceLabel` |
| Social | `recordSwipe`, `unmatchUser`, `blockUser`, `reportUser`, message/match notifications |
| Video | `createVideoCall`, `respondToVideoCall`, `endVideoCall`, `expireVideoCall` |
| Spotify | `spotifyCompleteAuth` (+ music link/sync helpers used by the client) |
| Relationship | `saveRelationshipAnswer`, `getRelationshipAnswered`, `getRelationshipMatches` |
| Match score | `seedMatchScoreOnUserCreate`, `awardMatchBonusOnMatchCreate`, `submitMatchFeedback` |
| Boost | `verifyBoostPurchase`, `activateBoost`, `expireBoost` |
| Account | `deleteUserAccount`, `exportMyData`, `syncAuthAccount` |

### Projects / flavors

| Flavor | Dart entry | Application ID (typical) | Firebase options project |
| --- | --- | --- | --- |
| development | `lib/main_development.dart` | `com.mevora.app.dev` | `mevora-d6ed0` (live options in current bootstrap) |
| staging | `lib/main_staging.dart` | `com.mevora.app.staging` | `mevora-staging` |
| production | `lib/main_production.dart` | `com.mevora.app` | `mevora-production` |

`.firebaserc` also defines aliases `mevora-dev` / `mevora-staging` / `mevora-production` for CLI deploys. Confirm the active project before deploying rules or functions.

---

## Environments

Development can target the Emulator Suite for **Firestore / Functions / Storage**. Phone Auth usually uses the **live** Firebase project because the Auth emulator cannot send real SMS. Optional:

```bash
--dart-define=USE_AUTH_EMULATOR=true
--dart-define=USE_EMULATORS=false
```

---

## Getting started

### Prerequisites

- Flutter SDK compatible with `sdk: ^3.11.5` (see `pubspec.yaml`)
- Xcode / Android Studio as needed
- Node.js for Cloud Functions
- Firebase CLI (`npx -y firebase-tools@latest` recommended)

### Install & run

```bash
flutter pub get

# Optional: Firestore emulator
npx -y firebase-tools@latest emulators:start --only firestore --project mevora-d6ed0

# Development flavor
flutter run --flavor development -t lib/main_development.dart
```

Other flavors:

```bash
flutter run --flavor staging -t lib/main_staging.dart
flutter run --flavor production -t lib/main_production.dart
```

Physical devices are recommended for real SMS and push. Android emulators use `10.0.2.2` for host loopback when talking to local emulators.

### Functions

```bash
cd functions
npm install
npm run build
# Deploy only after selecting the correct Firebase project
```

---

## Testing

```bash
flutter analyze
flutter test
```

Tests cover policies (chat, discovery activity, match score, music, relationship), widgets, call state machine, localization formatting, and selected security-rules contracts under `test/security/`.

---

## Localization

| Locale | File |
| --- | --- |
| English | `lib/l10n/app_en.arb` |
| Turkish | `lib/l10n/app_tr.arb` |

Generated with Flutter gen-l10n (`l10n.yaml`). Runtime language selection lives under settings / `LanguageScope`.

---

## Animations (Rive)

Compact `.riv` assets under `assets/rive/` with a safe Flutter fallback (`MevoraRiveAnimation`). Typical uses:

| Moment | Asset family |
| --- | --- |
| Loading / music sync | `common/searching.riv` |
| Match celebration | `matching/match.riv` |
| Empty discovery / matches / chat | feature empty rivs |
| Login / Spotify idle | `authentication/login_ambient.riv` |
| Relationship accent | onboarding / look family |

Inventory and mapping: [`assets/rive/ASSETS.md`](assets/rive/ASSETS.md).

---

## Security & privacy

- Firestore rules: `firebase/firestore.rules`
- Storage rules: `firebase/storage.rules`
- Exact GPS is owner-only; discovery surfaces **labels**, not coordinates
- Clients cannot spoof another user’s `auth.uid`
- Boost and purchase verification are server-side

Deeper write-ups: [FIREBASE_SECURITY.md](FIREBASE_SECURITY.md), [LOCATION_ARCHITECTURE.md](LOCATION_ARCHITECTURE.md).

---

## Documentation map

| Topic | Document |
| --- | --- |
| Product phases | [MEVORA_DEVELOPMENT.md](MEVORA_DEVELOPMENT.md) |
| App architecture | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Firebase overview | [FIREBASE_ARCHITECTURE.md](FIREBASE_ARCHITECTURE.md) |
| Firebase setup | [FIREBASE_SETUP.md](FIREBASE_SETUP.md) |
| Data model | [FIREBASE_DATA_ARCHITECTURE.md](FIREBASE_DATA_ARCHITECTURE.md) |
| Phone auth | [PHONE_AUTH_IMPLEMENTATION.md](PHONE_AUTH_IMPLEMENTATION.md) |
| Location privacy | [LOCATION_ARCHITECTURE.md](LOCATION_ARCHITECTURE.md) |
| Boost / IAP | [PAYMENT_ARCHITECTURE.md](PAYMENT_ARCHITECTURE.md) |
| Localization | [LOCALIZATION_ARCHITECTURE.md](LOCALIZATION_ARCHITECTURE.md) |

---

## Secrets

Do **not** commit:

- `.env`, `*.jks`, `key.properties`, service-account JSON
- LiveKit API keys/secrets, Spotify client secret, Apple IAP private keys

Configure in Firebase / store consoles and pass public client IDs via `--dart-define` when needed (for example `SPOTIFY_CLIENT_ID`).

### Manual production checklist

1. **LiveKit** — `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_URL` as Functions secrets; enable `videoCallsEnabled` only when ready
2. **APNs** — upload key in Firebase Cloud Messaging for iOS push
3. **Play / SHA** — fingerprints registered for Google Sign-In and FCM
4. **IAP** — Boost products created in App Store Connect / Play Console matching the pack IDs

---

## Key dependencies

| Package | Use |
| --- | --- |
| `go_router` | Navigation + shell tabs |
| `firebase_*` / `cloud_*` | Auth, Firestore, Storage, Functions, FCM, Crashlytics, Analytics, App Check |
| `google_sign_in` / `sign_in_with_apple` | Social auth |
| `geolocator` / `permission_handler` | Location & permissions |
| `in_app_purchase` | Boost packs |
| `rive` | Motion accents |
| `livekit_client` | Video media |
| `record` / `audioplayers` | Voice messages |
| `image_picker` | Photos |
| `app_links` / `url_launcher` | OAuth / deep links |

---

## License

Private and proprietary. All rights reserved.
