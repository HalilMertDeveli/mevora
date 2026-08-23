# MEVORA Architecture

Last updated: 2026-08-23 (performance refactor pass).

## 1. Project structure

```
lib/
  core/           # Theme, routing, DI scopes, errors, network, constants
  features/       # Feature modules (auth, discovery, chat, …)
  shared/         # Cross-feature widgets, images, animations
  l10n/           # Generated + ARB localization
functions/        # Firebase Cloud Functions (TypeScript)
firebase/         # Firestore + Storage rules, indexes
test/             # Unit, widget, integration tests
docs/             # Architecture & audit documentation
```

## 2. Feature structure

Each feature follows **data → domain → presentation** where practical:

| Layer | Responsibility |
|-------|----------------|
| `presentation/` | Widgets, pages, `ChangeNotifier` controllers |
| `domain/` | Entities, repository interfaces, use-case style services |
| `data/` | Repository implementations, Firebase/CF data sources |

Not every feature has full clean-arch layers; only add abstraction when it reduces duplication or improves testability.

## 3. Presentation

- Screens are `StatefulWidget` or thin wrappers.
- Controllers extend `ChangeNotifier` and live in feature scopes (`DiscoveryScope`, `SocialScope`, etc.).
- Widgets must **not** call `FirebaseFirestore.instance` directly.

## 4. Domain

- `Result<T>` (`Success` / `Err`) for repository outcomes.
- Typed failures via `Failure` hierarchy + `FailureMapper`.
- Business rules in services (e.g. `MevoraCompatibilityEngine`, `DiscoveryRankingEngine`).

## 5. Data

- `DiscoveryRepository` → Cloud Function `getDiscoveryCandidates` (+ mock/in-memory for tests).
- `RelationshipRepository` → Cloud Functions + Firestore owner-read for saved answers.
- Profile, chat, matching each have dedicated repositories/data sources.

## 6. Repository pattern

Repositories are the **only** layer presentation/controllers should use for remote data:

- `DiscoveryRepository`
- `RelationshipRepository` (+ `getSavedAnswers`)
- `ChatRepository`, `ProfileRepository`, etc.

Inject via `InheritedWidget` scopes created in `lib/core/di/`.

## 7. Use cases

Formal use-case classes are used sparingly. Controllers orchestrate:

```
DiscoverScreen → DiscoveryController → DiscoveryRepository → CF/Firestore
```

Compatibility breakdown mapping lives in `CompatibilityBreakdownMapper`; session cache in `CompatibilitySessionCache`.

## 8. State management

- **ChangeNotifier + InheritedWidget scopes** (not Riverpod/Bloc).
- Feature-scoped controllers; avoid global singletons for UI state.
- `ProfileUpdateNotifier` broadcasts profile saves to invalidate discovery cache.

## 9. Firebase

| Service | Usage |
|---------|--------|
| Auth | Email, phone, social sign-in |
| Firestore | Profiles, chat, blocks, relationship answers (owner subcollection) |
| Storage | Profile photos (original / medium / thumb where available) |
| Functions | Discovery candidates, swipes, relationship test, payments |

Security rules in `firebase/firestore.rules` — server-authoritative fields must not be client-writable.

## 10. Caching

| Cache | Scope | Invalidation |
|-------|-------|--------------|
| `CompatibilitySessionCache` | In-memory per discovery session | `onProfileUpdated()` |
| Flutter `ImageCache` | Network images | OS memory pressure |
| Discovery deck | Controller state + cursor pagination | Radius/filter change, profile update |

## 11. Compatibility Engine

- **Server:** Primary score + category breakdown in discovery CF response.
- **Client:** `MevoraCompatibilityEngine` for hidden insight card and mock paths.
- **UI:** `CompatibilityBreakdownMapper` + `WhyYouMatchPanel`; `DiscoveryController.breakdownFor()` caches breakdown per viewer/candidate pair.

## 12. Discover

Flow:

1. `DiscoveryController.loadCandidates(refresh: true)` — first page (limit 15).
2. Swipe removes head; when stack ≤ 3, `_maybePrefetchMore()` appends via cursor.
3. Empty deck → `_reloadWhenDeckEmpty()` uses cursor before full refresh.
4. Photos prefer `thumbUrl` in repository parsing.

## 13. Chat

- `ChatController` with realtime listener (limit 30).
- Messages list precomputes reversed order once per rebuild (not per row).
- Scroll listener removed in `dispose`.

## 14. Error handling

- Repositories catch Firebase/CF errors → `Result` + `Failure`.
- UI uses `l10n_errors` / localized strings — not raw exception text.

## 15. Testing

- `InMemoryDiscoveryRepository` / `MockRelationshipDataSource` for unit tests.
- Widget tests under `test/features/`.
- Run `flutter analyze` and targeted `flutter test` after refactors.

## Refactor changelog (2026-08-23)

- Wired discovery cursor pagination + prefetch threshold.
- Chat ListView O(n²) fix + scroll listener dispose.
- Discovery thumb-first image URLs; prefetch listener cleanup.
- Relationship answers via `RelationshipRepository.getSavedAnswers`.
- `CompatibilitySessionCache` wired via `breakdownFor()`.
