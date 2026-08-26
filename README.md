<p align="center">
  <a href="README.md">English</a> · <a href="README.tr.md">Türkçe</a>
</p>

<p align="center">
  <img src="docs/images/mevora-hero.png" alt="Mevora login hero" width="850" />
</p>

<h1 align="center">💜 Mevora</h1>

<p align="center">
  <strong>Discover people. Understand compatibility. Start something meaningful.</strong>
</p>

<p align="center">
  Mevora is a Flutter + Firebase dating app for iOS and Android. It combines swipe discovery with interest matching, music taste signals, relationship-view questions, and server-enforced safety — without exposing exact GPS to other users.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.11+-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Firebase-Backend-FFCA28?logo=firebase&logoColor=black" alt="Firebase" />
  <img src="https://img.shields.io/badge/Platform-iOS%20%7C%20Android-lightgrey" alt="Platform" />
  <img src="https://img.shields.io/badge/Locale-EN%20%7C%20TR-blue" alt="Locales" />
  <img src="https://img.shields.io/badge/Status-Private%20%2F%20Active%20Development-orange" alt="Status" />
</p>

<p align="center">
  <code>com.mevora.app</code> · production Firebase project: <code>mevora-production</code>
</p>

---

## Table of contents

- [At a glance](#at-a-glance)
- [Screenshots & visuals](#screenshots--visuals)
- [What is Mevora?](#what-is-mevora)
- [How it works](#how-it-works)
- [Compatibility engine](#compatibility-engine)
- [Relationship question system](#relationship-question-system)
- [Safety & trust](#safety--trust)
- [Photo moderation](#photo-moderation)
- [Feature matrix](#feature-matrix)
- [Tech stack](#tech-stack)
- [Architecture](#architecture)
- [Firebase architecture](#firebase-architecture)
- [Project structure](#project-structure)
- [Security](#security)
- [Testing](#testing)
- [Production smoke test](#production-smoke-test)
- [Getting started](#getting-started)
- [Environments & secrets](#environments--secrets)
- [Recent development](#recent-development)
- [Roadmap](#roadmap)
- [Documentation map](#documentation-map)
- [License](#license)

---

## At a glance

| | |
| --- | --- |
| **Type** | 18+ dating & social discovery |
| **Architecture** | Feature-first Clean Architecture |
| **State** | `ChangeNotifier` controllers + `InheritedWidget` scopes |
| **Routing** | `go_router` with tab shell |
| **Backend** | Firebase Auth, Firestore, Storage, Cloud Functions, FCM |
| **Locales** | English · Turkish (`gen-l10n`) |
| **Store status** | Private repository — not a public store release claim |

---

## Screenshots & visuals

Captured from the **development flavor** on Android emulator plus in-app portrait assets used on Discover cards. Paths are relative so images render on GitHub.

### App screens (live UI captures)

<p align="center">
  <img src="docs/images/mevora-login.png" alt="Login welcome" width="220" />
  <img src="docs/images/mevora-register.png" alt="Create account" width="220" />
  <img src="docs/images/mevora-login-email.png" alt="Email sign-in" width="220" />
</p>

<p align="center">
  <img src="docs/images/mevora-phone.png" alt="Phone sign-in" width="220" />
  <img src="docs/images/mevora-discover-sample.png" alt="Discover card photo sample" width="220" />
  <img src="docs/images/mevora-profile-sample.png" alt="Profile photo sample" width="220" />
</p>

| Screen | File | Notes |
| --- | --- | --- |
| Login / welcome | `docs/images/mevora-login.png` | Google · Apple · email · phone entry |
| Register | `docs/images/mevora-register.png` | Account creation flow |
| Email sign-in | `docs/images/mevora-login-email.png` | Email + password form |
| Phone sign-in | `docs/images/mevora-phone.png` | OTP entry screen |
| Hero banner | `docs/images/mevora-hero.png` | Login hero asset (`login_background.jpg`) |
| Discover portraits | `docs/images/portrait-0N.jpg` | Mock portraits used on Discover cards |

### Discovery portrait samples (in-app assets)

<p align="center">
  <img src="docs/images/portrait-01.jpg" alt="Portrait sample" width="120" />
  <img src="docs/images/portrait-02.jpg" alt="Portrait sample" width="120" />
  <img src="docs/images/portrait-03.jpg" alt="Portrait sample" width="120" />
  <img src="docs/images/portrait-04.jpg" alt="Portrait sample" width="120" />
  <img src="docs/images/portrait-05.jpg" alt="Portrait sample" width="120" />
  <img src="docs/images/portrait-06.jpg" alt="Portrait sample" width="120" />
</p>

| Area | In app | Status |
| --- | --- | --- |
| Login / welcome | `authentication` feature | Implemented |
| Phone OTP | `/phone` flow | Implemented |
| Onboarding & profile | multi-step wizard | Implemented |
| Discover / swipe | card stack + actions | Implemented |
| Match celebration | Rive accent | Implemented |
| Chat | text, image, GIF, voice | Implemented |
| Music tab | Spotify-linked taste UI | Implemented |
| Boost / IAP | consumable packs | Implemented |
| Video calls | LiveKit provider | Implemented, **feature flag off by default** |
| Full authenticated UI screenshot set | Discover · Match · Chat tabs | **Partial** — auth screens captured; main tabs need signed-in device run |

### Screen coverage map

| Login / auth | Onboarding / profile | Discover / swipe |
| --- | --- | --- |
| Implemented | Implemented | Implemented |
| Match / celebration | Chat | Settings / safety |
| Implemented | Implemented | Implemented |
| Music tab | Boost / IAP | Relationship questions |
| Implemented | Implemented | Implemented |
| Video calls | Photo moderation (backend) | — |
| Implemented, flag off | Implemented (no AI) | — |

---

## What is Mevora?

Mevora helps people find connections they are likely to click with through:

- **Personalized discovery** — server-side candidate feed with filters (age, distance, gender prefs, activity window)
- **Compatibility signals** — shared interests, relationship goals, music taste, relationship Q&A alignment
- **Match Score** — server-side scoring and post-match feedback prompts
- **Safety tooling** — 18+ gate, report, block, unmatch, account deletion, photo moderation pipeline
- **Privacy-first location** — distance labels from Cloud Functions; other users never receive raw coordinates

Mevora is **not** marketed here as “AI-powered matching” or “guaranteed matches.” Signals are rule-based and server-validated.

---

## How it works

```mermaid
flowchart TD
    A[Sign in] --> B[Onboarding & profile]
    B --> C[Upload photos]
    C --> D[Server moderation]
    D --> E[Discover feed]
    E --> F{Like / Pass / Super Like}
    F -->|Mutual like| G[Match]
    G --> H[Chat]
    H --> I[Block / Report / Unmatch]
    I --> J[Account deletion optional]
```

**Typical user path**

1. Authenticate (email, Google, Apple, phone, optional Spotify when enabled)
2. Complete onboarding (18+, bio, interests, lifestyle, min **3** photos)
3. `completeOnboarding` callable validates age + approved photos server-side
4. Discovery loads via `getDiscoveryCandidates` / `getDiscoveryFeed`
5. Mutual likes create matches (`recordSwipe` / `recordDiscoveryDecision`)
6. Chat writes to `matches/{id}/messages` under Firestore rules
7. Safety actions call `blockUser`, `reportUser`, `unmatchUser`
8. `deleteUserAccount` removes Auth + Firestore + Storage data

---

## Compatibility engine

Discovery ranking combines several **independent signals**. Values below are taken from the current Cloud Functions / domain code.

### Profile compatibility score (`compatibilityScore`)

Used in `getDiscoveryCandidates` (`functions/src/backend.ts`):

| Signal | Rule | Max contribution |
| --- | --- | --- |
| Shared interests | `min(25, sharedCount × 5)` | **25** |
| Same relationship goal | `+20` if goals match | **20** |
| **Total** | rounded integer | **45** |

This score is **not** a percentage and does not alone create a match.

### Music compatibility (separate field)

Client calculator (`music_compatibility.dart`):

| Component | Weight |
| --- | --- |
| Shared tracks | 40% |
| Shared artists | 30% |
| Shared genres | 20% |
| Recent listening habits | 10% |

Backend also applies a **ranking bonus** (`musicRankingBonus`) — music never replaces dating compatibility or auto-creates matches.

### Relationship compatibility (separate field)

When both users answered the same relationship questions:

```text
score = round(alignedCount / sharedQuestionCount × 100)
```

Relationship suggestions from `getRelationshipMatches` are **not** automatic mutual swipe matches.

### Other discovery filters (server-side)

- Self, blocked, liked, passed, active match partners excluded
- 90-day activity window on `users.lastActiveAt`
- Gender preference mutual check
- Min **3 approved** photos, 18+, account eligibility
- Radius presets: 5 / 10 / 25 / 50 / 100 km
- Boost visibility sorting (`sortByBoostVisibility`)

---

## Relationship question system

Implemented in `lib/features/relationship/` with **110+ catalog questions**, each with **3 answer options**, presented in fixed **3-question sessions** so two users can share answer keys.

### Topics in catalog (`RelationshipTopic`)

| Topic | Examples of theme |
| --- | --- |
| `jealousy` | Boundaries around jealousy |
| `trust` | Trust expectations |
| `loyalty` | Commitment signals |
| `communication` | How you talk through conflict |
| `boundaries` | Personal limits |
| `socialLife` | Nights out, social energy |
| `friendship` | Friend vs partner balance |
| `personalSpace` | Alone time |
| `futurePlans` | Long-term direction |
| `money` | Financial habits |
| `flirting` | Flirting boundaries |
| `exes` | Past relationships |
| `expectations` | What you expect from a partner |

Prompts and answers are localized (**EN / TR**). Cloud Functions: `saveRelationshipAnswer`, `getRelationshipAnswered`, `getRelationshipMatches`, `completeRelationshipTest`.

```mermaid
flowchart LR
    Q[3-question session] --> A[User answers]
    A --> S[Stored per user]
    S --> C[Compatibility key]
    C --> R[Discovery / suggestion signals]
```

---

## Safety & trust

| Feature | Status | Notes |
| --- | --- | --- |
| 🔞 18+ age gate | Implemented | Client validators + `completeOnboarding` + `profileSafety.ts` |
| 🔐 Server-side onboarding flags | Implemented | Clients cannot set `isDiscoverable` directly |
| 🛡️ Report user | Implemented | Whitelist reasons, 20/day limit |
| 🚫 Block user | Implemented | `blocks/` + `users/.../blockedUsers/` |
| Unmatch | Implemented | Deactivates match server-side |
| Message rate limit | Implemented | 20/min per match, 60/min global |
| Discovery safety sheet | Implemented | Hide / block / report from profile |
| 🗑️ Account deletion | Implemented | `deleteUserAccount` callable |
| 📍 Location privacy | Implemented | GPS owner-only; others get distance labels |
| 📸 Photo moderation | Implemented | Technical pipeline, no AI (see below) |
| Profile read enumeration hardening | In progress | `profiles` still readable to authenticated users |
| AI content moderation | Planned | Architecture allows future provider |

---

## Photo moderation

Current implementation is **server-controlled** and does **not** use AI/ML image classification.

```mermaid
stateDiagram-v2
    [*] --> pending: Client upload to Storage pending/
    pending --> processing: onProfilePhotoUploaded
    processing --> approved: Technical checks pass
    processing --> manual_review: Dimensions unverified
    processing --> rejected: Invalid type/size/corrupt
    manual_review --> approved: Manual ops (future UI)
    reportUser --> manual_review: Report pipeline
    approved --> [*]: Visible in discovery
    rejected --> [*]: Hidden from discovery
```

| Stage | Owner |
| --- | --- |
| Upload | Client → `users/{uid}/profile/pending/` |
| Publish to `photos/` | Cloud Functions only |
| Status fields | `moderationStatus`, `moderatedBy`, `moderationReason` |
| Client escalation guard | `enforceProfilePhotoModeration` trigger |

Details: [docs/PHOTO_MODERATION.md](docs/PHOTO_MODERATION.md)

---

## Feature matrix

| Feature | Status |
| --- | --- |
| Email / password auth | Implemented |
| Google Sign-In | Implemented |
| Sign in with Apple | Implemented |
| Phone OTP | Implemented |
| Spotify login | Implemented, **off by default** (`FeatureFlags.spotifyLoginEnabled`) |
| Multi-step onboarding | Implemented |
| Profile edit & settings | Implemented |
| Photo upload (min 3, max 6) | Implemented |
| Discover / swipe | Implemented |
| Like / pass / super like | Implemented |
| Mutual match creation | Implemented (server authoritative) |
| Compatibility scoring | Implemented |
| Relationship questions | Implemented |
| Music match / Spotify taste | Implemented |
| Match Score & feedback | Implemented |
| Text / image / GIF / voice chat | Implemented |
| Push notifications (FCM) | Implemented |
| Block / report / unmatch | Implemented |
| Boost IAP (consumable) | Implemented |
| Subscriptions | **Disabled placeholder** only |
| Video calls (LiveKit) | Implemented, **feature flag off by default** |
| Photo moderation pipeline | Implemented (technical, no AI) |
| Firebase App Check | Implemented |
| Crashlytics & Analytics | Implemented |
| Firebase Remote Config SDK | **Not wired** — local defaults via `MevoraRemoteConfig` |
| Automated device E2E | Partial (`integration_test/`, needs device) |
| Backend production smoke harness | Implemented (`tools/smoke/`) |
| CI workflow | Implemented (`.github/workflows/smoke.yml`) |

---

## Tech stack

| Layer | Technology |
| --- | --- |
| Mobile | Flutter |
| Language | Dart `^3.11.5` |
| Navigation | `go_router` |
| State / DI | `ChangeNotifier` + scope widgets |
| Auth | Firebase Auth |
| Database | Cloud Firestore |
| Files | Firebase Storage |
| Logic | Cloud Functions (Node 20, TypeScript) |
| Push | Firebase Cloud Messaging |
| Crashes | Firebase Crashlytics |
| Analytics | Firebase Analytics |
| Attestation | Firebase App Check |
| Maps / location | `geolocator`, server-side distance |
| Purchases | `in_app_purchase` (Boost packs) |
| Motion | Rive |
| Video | LiveKit (`livekit_client`) |
| Voice chat media | `record`, `audioplayers` |

---

## Architecture

```mermaid
flowchart TB
    subgraph Presentation
        Pages[Pages / Widgets]
        Ctrl[Controllers]
    end
    subgraph Domain
        Ent[Entities & policies]
        Repo[Repository interfaces]
    end
    subgraph Data
        Impl[Repository implementations]
        DS[Firebase / SDK datasources]
    end
    subgraph Backend
        CF[Cloud Functions]
        FS[(Firestore)]
        ST[(Storage)]
    end
    Pages --> Ctrl
    Ctrl --> Repo
    Impl --> Repo
    Impl --> DS
    DS --> FS
    DS --> ST
    DS --> CF
    CF --> FS
    CF --> ST
```

**Rules**

- No Riverpod / Bloc / GetIt — constructor injection + scopes (`AuthScope`, `DiscoveryScope`, …)
- Presentation never imports Firebase SDK types directly for business rules
- Matching rules oracle: `MatchEngine` (shared with Functions semantics)

Deep dive: [ARCHITECTURE.md](ARCHITECTURE.md)

---

## Firebase architecture

```mermaid
flowchart LR
    App[Flutter App]
    App --> Auth[Firebase Auth]
    App --> FS[(Firestore)]
    App --> ST[(Storage)]
    App --> CF[Cloud Functions]
    App --> FCM[FCM]
    App --> AC[App Check]
    CF --> FS
    CF --> ST
    CF --> Auth
    Trg[Storage trigger] --> CF
```

**Key collections**

| Path | Purpose |
| --- | --- |
| `users/{uid}` | Private account (owner read) |
| `profiles/{uid}` | Public dating card |
| `userPreferences/{uid}` | Discovery prefs |
| `userLocation/{uid}` | GPS (server-side reads for distance) |
| `matches/{id}` | Active matches |
| `matches/{id}/messages` | Chat |
| `likes/{from}_{to}` | Swipe records (server writes) |
| `blocks/{blocker}_{blocked}` | Blocks |
| `reports/{id}` | User reports |

References: [FIREBASE_ARCHITECTURE.md](FIREBASE_ARCHITECTURE.md) · [FIREBASE_DATA_ARCHITECTURE.md](FIREBASE_DATA_ARCHITECTURE.md)

---

## Project structure

```text
Mevora/
├── lib/
│   ├── core/           config, routing, theme, DI, Firebase bootstrap
│   ├── features/
│   │   ├── authentication/
│   │   ├── onboarding/
│   │   ├── profile/
│   │   ├── discovery/
│   │   ├── matching/
│   │   ├── match_score/
│   │   ├── relationship/
│   │   ├── music/
│   │   ├── chat/
│   │   ├── calls/
│   │   ├── boost/
│   │   ├── safety/
│   │   ├── settings/
│   │   └── …
│   ├── shared/         design system, Rive wrappers
│   └── l10n/
├── functions/src/      Cloud Functions + moderation + smoke helpers
├── firebase/           Firestore/Storage rules, indexes, rules tests
├── test/               unit + widget + security contract tests
├── integration_test/   device E2E entry (requires connected device)
├── tools/smoke/        backend production smoke runner
├── mevora-support-web/ independent ASP.NET Core support & landing site
└── docs/               architecture & runbooks
```

## Support Website

The Mevora repository also contains an independent ASP.NET Core support website located at:

`/mevora-support-web`

See [`mevora-support-web/README.md`](mevora-support-web/README.md) for local run, Firebase, email, and domain setup.

---

## Security

- **Firestore rules** — lifecycle fields, blocks, reports, server-only purchases/rate limits
- **Storage rules** — clients upload `pending/` only; `photos/` publish is Functions-only
- **App Check** — debug providers in dev/staging; Play Integrity / App Attest in production
- **Server validation** — onboarding completion, swipes, boosts, reports, deletion
- **18+ enforcement** — client + `completeOnboarding` + discovery filters
- **Smoke test isolation** — `isSmokeTestUser` is server-only; smoke users only see each other in discovery

More: [FIREBASE_SECURITY.md](FIREBASE_SECURITY.md) · [LOCATION_ARCHITECTURE.md](LOCATION_ARCHITECTURE.md)

---

## Testing

| Layer | Location | Status |
| --- | --- | --- |
| Unit / widget tests | `test/` (~120 files) | Implemented |
| Cloud Functions tests | `functions/test/` (41 tests) | Implemented |
| Firestore rules tests | `firebase/tests/` | Implemented |
| Security contract tests | `test/security/` | Implemented |
| Integration config test | `test/integration/` | Implemented |
| Device E2E | `integration_test/smoke/` | Partial — needs Android/iOS device |
| Backend smoke | `tools/smoke/run_smoke_test.mjs` | Implemented |
| CI | `.github/workflows/smoke.yml` | Implemented |

```bash
# Flutter (default scope via dart_test.yaml)
flutter analyze
flutter test

# Cloud Functions
cd functions && npm test

# Firestore / moderation integration
cd firebase/tests && npm test

# Backend smoke (requires service account — never commit credentials)
cd tools/smoke && npm install
# set GOOGLE_APPLICATION_CREDENTIALS, then:
node run_smoke_test.mjs
```

Smoke flow documentation: [docs/SMOKE_TEST.md](docs/SMOKE_TEST.md)

---

## Production smoke test

Backend smoke harness validates critical production flows against **real Firebase state** (not fake UI success).

```mermaid
flowchart TD
    R[Register / seed smoke users] --> A[18+ validation]
    A --> P[3 photos]
    P --> M[Moderation pipeline]
    M --> D[Discover]
    D --> L[Like]
    L --> MT[Match]
    MT --> MSG[Message]
    MSG --> BL[Block]
    BL --> RP[Report]
    RP --> DEL[Delete account]
    DEL --> CL[Cleanup]
```

| Component | Location | Status |
| --- | --- | --- |
| Backend runner | `tools/smoke/run_smoke_test.mjs` | Implemented |
| Smoke users | `smoke-a@mevora.test`, `smoke-b@mevora.test` | Implemented |
| Isolation flag | `users.isSmokeTestUser` (server-only) | Implemented |
| Device E2E | `integration_test/smoke/` | Partial — requires connected device |
| CI workflow | `.github/workflows/smoke.yml` | Implemented |

Run with a **service account** (never commit credentials). See [docs/SMOKE_TEST.md](docs/SMOKE_TEST.md).

---

## Getting started

### Prerequisites

- Flutter SDK compatible with `sdk: ^3.11.5`
- Xcode / Android Studio
- Node.js 20+ for Cloud Functions
- Firebase CLI

### Install & run

```bash
git clone https://github.com/HalilMertDeveli/mevora.git
cd mevora
flutter pub get

# Development flavor
flutter run --flavor development -t lib/main_development.dart

# Staging
flutter run --flavor staging -t lib/main_staging.dart

# Production flavor (local testing only — use with care)
flutter run --flavor production -t lib/main_production.dart
```

### Cloud Functions

```bash
cd functions
npm install
npm run build
# Confirm Firebase project before deploy:
# firebase deploy --only functions,firestore:rules,storage --project mevora-production
```

### Emulators (optional)

```bash
firebase emulators:start --only firestore,functions,storage,auth
flutter run --dart-define=USE_EMULATORS=true -t lib/main_development.dart
```

Phone Auth typically needs a **live** Firebase project for real SMS unless using test numbers / Auth emulator.

---

## Environments & secrets

| Flavor | Entry | Package (typical) | Firebase project |
| --- | --- | --- | --- |
| development | `main_development.dart` | `com.mevora.app.dev` | `mevora-d6ed0` |
| staging | `main_staging.dart` | `com.mevora.app.staging` | `mevora-staging` |
| production | `main_production.dart` | `com.mevora.app` | `mevora-production` |

**Never commit:** `.env`, keystores, service account JSON, Spotify client secret, LiveKit secrets, Apple signing keys.

Public client IDs may be passed via `--dart-define` (e.g. `SPOTIFY_CLIENT_ID`). See [FIREBASE_SETUP.md](FIREBASE_SETUP.md).

---

## Recent development

| Commit | Summary |
| --- | --- |
| `docs` | Visual README PNG assets + live auth screen captures |
| `4853442` | README screen map + production smoke flow |
| `901fafd` | Comprehensive visual README with verified project analysis |
| `8946ffb` | Production hardening, photo moderation pipeline, smoke tests, compliance tests |
| `11fbba3` | Relationship survey timing tuning |
| `7c8f1d0` | README + asset visuals |
| `5cdac15` | Phone auth synced with shared `AuthController` |
| `cef0595` | Boost IAP, Rive UI, logout stability |

---

## Roadmap

Verified gaps / planned improvements (not implemented as full products yet):

- AI/ML photo moderation provider (architecture ready, not active)
- Firebase Remote Config SDK integration (defaults exist in code only)
- Stronger profile read model (reduce authenticated enumeration surface)
- Full device E2E smoke on CI (App Check + Test Lab strategy)
- Live subscriptions (placeholder module only today)
- Admin moderation console for `manual_review` photos
- Expanded analytics for safety events

---

## Documentation map

| Topic | Document |
| --- | --- |
| Architecture | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Firebase overview | [FIREBASE_ARCHITECTURE.md](FIREBASE_ARCHITECTURE.md) |
| Data model | [FIREBASE_DATA_ARCHITECTURE.md](FIREBASE_DATA_ARCHITECTURE.md) |
| Photo moderation | [docs/PHOTO_MODERATION.md](docs/PHOTO_MODERATION.md) |
| Smoke testing | [docs/SMOKE_TEST.md](docs/SMOKE_TEST.md) |
| Phone auth | [PHONE_AUTH_IMPLEMENTATION.md](PHONE_AUTH_IMPLEMENTATION.md) |
| Boost / IAP | [PAYMENT_ARCHITECTURE.md](PAYMENT_ARCHITECTURE.md) |
| Localization | [LOCALIZATION_ARCHITECTURE.md](LOCALIZATION_ARCHITECTURE.md) |
| Rive assets | [assets/rive/ASSETS.md](assets/rive/ASSETS.md) |

---

## License

Private and proprietary. All rights reserved.
