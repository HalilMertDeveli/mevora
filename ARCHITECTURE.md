# Mevora architecture

Mevora is a Flutter dating app. The goal is a codebase that can grow (new auth
providers, a later AI compatibility strategy, video SDK swaps) without rewriting
screens — and without a forest of one-line classes.

This document describes the architecture as implemented. Product phases live in
`MEVORA_DEVELOPMENT.md`.

## Overview

```text
UI (widgets)
  → Controller / ChangeNotifier
    → Use case (only when there is real logic)
      → Repository interface (domain)
        → Repository impl + DTO/mapper (data)
          → Firebase / device SDK
```

- **Presentation** owns widgets, navigation, and user-facing copy.
- **Domain** owns entities, policies, and repository contracts. No Flutter UI
  types, no `cloud_firestore` / `firebase_auth` types.
- **Data** owns Firebase and other SDKs, maps exceptions to `AppException`,
  then `FailureMapper` to `Failure`.
- **Core** is shared infrastructure: config, routing, errors, logging, theme,
  analytics/storage/notification ports, paging, cache.

There is **one** DI approach: constructor injection plus `InheritedWidget`
scopes (`AppScope`, `AuthScope`, `SocialScope`). Riverpod/GetIt are not used.

## Folder layout

```text
lib/
├── core/           config, routing, errors, theme, logging, contracts
├── di/             SocialScope composition for chat/match/calls
├── features/
│   ├── authentication/   data | domain | presentation
│   ├── onboarding/
│   ├── profile/
│   ├── location/
│   ├── discovery/        CompatibilityEngine lives here
│   ├── matching/
│   ├── chat/
│   ├── calls/            video call SDK adapter + UI
│   ├── video/            feature-flagged VideoCallProvider skeleton
│   ├── notifications/
│   ├── safety/
│   ├── settings/
│   └── subscription/     flag + disabled repository only
├── shared/         design-system widgets used by multiple features
└── main_*.dart     environment entrypoints
```

Features talk to each other through **domain types and repository interfaces**,
never through another feature's `data/` or widget internals.

## Dependency rules

1. `presentation` → `domain` (and `core`, `shared`). Never Firebase.
2. `domain` → `core` only. Never Flutter widgets, never Firebase.
3. `data` → `domain` + Firebase/SDK. Maps DTO → entity.
4. `core` does not import `features/` except routing/DI composition roots.
5. No circular feature imports. Profile entities may be read by discovery;
   chat depends on match ids, not match internals.

## SOLID (judiciously)

| Principle | How Mevora applies it |
| --- | --- |
| SRP | Auth adapters (email/google/apple/phone/spotify) are separate services. MatchEngine is the matching oracle. Controllers do not call Firestore. |
| OCP | `CompatibilityStrategy` for scoring. `VideoCallProvider` (calls feature) for media SDKs. `AnalyticsProvider`, `StorageProvider`, `LocationDevice`. |
| LSP | Fakes and Firebase impls honor the same repository contracts. |
| ISP | `MatchRepository`, `LikeRepository`, `ChatRepository`, `SafetyRepository`, `ProfileRepository` — not one UserService. |
| DIP | Widgets receive repositories/controllers from scopes. No `ChatRepository()` inside a widget. |

Skipped: tiny pass-through use cases (`watchAuth` is a repository stream).
Skipped: payment/admin/AI products beyond `FeatureFlags` and a disabled
subscription repository.

## State

`ChangeNotifier` controllers (`AuthController`, `ChatController`,
`MatchesController`, `CallController`) plus `go_router`'s
`refreshListenable`. No second state-management package.

Controllers that open streams (auth, chat, typing, presence, incoming calls)
must `dispose()`/`cancel()` those subscriptions. Chat typing is cleared on
dispose.

## Repositories and use cases

Important operations have either a use case or a named repository method:

- Auth: email, Google, Apple, Spotify (flagged), phone OTP, sign-out, delete
- Discovery: paginated `loadDiscoveryPage`
- Matching: `recordSwipe` (backend writes matches), `watchMatches`
- Chat: `sendText`, `watchLatest`, `loadOlder`, `markRead`, `setTyping`
- Video: start/accept/reject/end behind `videoCallsEnabled`
- Location: permission + coarse capture through `LocationRepository`

## DI

```text
bootstrap
  → AppConfig + AppLogger + FirebaseBootstrap
  → createAuthController(...)
  → MevoraApp(AppScope, AuthScope, optional SocialScope)
```

Tests inject `FakeAuthRepository`, `FakeChatRepository`, `FakeMatchRepository`,
`FakeLocationRepository`, `FakeVideoCallProvider`, and `FakeProfileRepository`.
Production constructs Firebase-backed impls in composition files, not in widgets.

## Errors

```text
SDK exception → AppException (data, sanitized message)
             → Failure (domain, FailureMapper)
             → FailureMessages / feature strings (presentation)
```

Never show raw Firebase codes or `e.message` from the SDK. `AuthErrorMapper`
is the auth-specific sanitizer.

`Result<T>` is `Success` | `Err`. Use `when` at the UI boundary.

## Firebase abstraction

| SDK | Port |
| --- | --- |
| Auth | `AuthRepository` + provider adapters |
| Firestore | feature data sources (`users`, `matches`, `messages`, …) |
| Storage | `StorageProvider` / profile image pipeline |
| FCM | `NotificationProvider` + `NotificationRepository` |
| Analytics | `AnalyticsProvider` (`FirebaseAnalyticsAdapter` / `NoopAnalyticsProvider`) |
| Crashlytics | `CrashReporter` |
| Video SDK | `VideoCallProvider` in `features/calls` |

Environments: development (`mevora-dev`, Firestore emulator; live Phone Auth unless `USE_AUTH_EMULATOR=true`), staging, production.
Secrets stay in `--dart-define` / CI. Spotify client **id** may ship; the
secret must not.

## Feature flags

`FeatureFlags` on `AppConfig`: `videoCallsEnabled`, `spotifyLoginEnabled`,
`premiumEnabled`, `aiRecommendationsEnabled`. Default **off**. Read flags in
use cases and composition, not as scattered widget `if`s.

## Analytics events

`AnalyticsEvents` in `lib/core/analytics/analytics_provider.dart`:
`sign_up`, `login`, `logout`, `onboarding_completed`, `profile_updated`,
`swipe_like`, `swipe_pass`, `swipe_super_like`, `match_created`,
`message_sent`, `report_submitted`, `user_blocked`, `account_deleted`,
`call_started`, `call_ended`.

Never attach email, phone, exact GPS, passwords, or tokens.

## Caching and pagination

`MemoryCache` is a TTL speed layer, not source of truth. Image memory is
capped by `ImageCachePolicy`. Discovery, matches, chat history, and
notifications paginate (`Page<T>` / `ChatPage` / discovery cursor).

## Navigation

Central `go_router` + `AuthRedirector`. Deep-link-ready paths:

- `/chat/:matchId`
- `/call/incoming/:callId`
- `/call/video/:callId`
- `/discovery`, `/matches`, `/profile`, `/settings`

Unauthenticated users hit login. Incomplete profiles hit onboarding.

## Testing

Fakes live next to tests (`test/helpers`) or as in-memory graph
(`InMemorySocialGraph`). Domain tests cover MatchEngine, CompatibilityEngine,
validators, and AuthRedirector. Widget tests cover design-system components
and the auth gate.

## Naming

- Entities: `UserProfile`, `AuthUser`, `Match`, `ChatMessage`
- Repositories: `FooRepository` (interface), `FooRepositoryImpl` / `FirebaseFoo…`
- Use cases: verbs (`RecordSwipeUseCase`, `CompleteOnboarding`)
- Failures vs exceptions: `AuthFailure` / `AuthException`

## Intentionally simple

- No payment/IAP system — `premiumEnabled` + `DisabledSubscriptionRepository`
- Boost one-time IAP is documented in `PAYMENT_ARCHITECTURE.md` (not a subscription)
- No admin app in this repo
- No AI matching implementation — add a `CompatibilityStrategy`
- Discovery UI still uses placeholders in some empty states; engine + cards exist
- Payments remain flags + Boost SKU placeholders, not a full IAP product
- `AppScope` remains the process-wide config/logger; do not add GetIt
- Auth/phone OTP use cases are thin repository wrappers kept because adapters
  behind them will change
- Pass-through `watchAuth` / `watchMatches` streams stay on repositories

## Remaining risks

- Two `VideoCallProvider` types: `features/calls` (LiveKit/Agora media) and
  `features/video` (flagged start/accept/reject/end skeleton). Do not merge
  them until one product API is chosen.
- Pagination DTO `ChatPage` shares a name with the chat screen widget. Import
  one library at a time, or prefix.
- Other agents may still be adding auth/chat/matching/boost. Prefer additive
  edits to `app_router.dart`, `MevoraApp`, `AuthController`, and Firebase adapters.
- `SocialErrorMapper` lives in core but reads presentation strings. Move it
  into matching/chat presentation when those features stabilize.
