# MEVORA — Architecture & Performance Audit (FAZ 0)

Audit date: 2026-08-23. Read-only analysis before refactor.

## 1. Initial problems

- **Discovery pagination exists server-side but not client-side** — `DiscoveryRepository.getCandidates` supports `cursor`/`nextCursor`, but `DiscoveryController.loadCandidates()` always fetches a fresh page and replaces the deck.
- **Full CF refetch on empty deck** — every time the swipe stack empties, `getDiscoveryCandidates` runs again from scratch (expensive: parallel likes/passed reads + per-candidate compatibility).
- **Chat ListView O(n²)** — `controller.messages.reversed.toList()` inside `itemBuilder` rebuilds the full list per row.
- **Chat scroll listener leak** — `_scroll.addListener(_onScroll)` without `removeListener` in `dispose`.
- **Image prefetch listeners** — `DiscoveryNetworkImage.prefetch` adds `ImageStreamListener` without removal.
- **Discovery cards load full-res URLs** — parser prefers `downloadUrl` over `thumbUrl`.
- **CompatibilitySessionCache** — allocated in `DiscoveryController` but only `invalidateViewer` used; no `get`/`put` on hot path.
- **Broad chat rebuilds** — single `AnimatedBuilder` on controller rebuilds entire scaffold (messages + composer + typing).

## 2. Architecture problems

- **Strengths:** Feature-first layout (`data/domain/presentation`), `InheritedWidget` DI scopes, `Result<T>` pattern, no direct Firestore in presentation widgets (except new `FirestoreRelationshipAnswersReader` used from settings — should move behind repository).
- **State:** `ChangeNotifier` + scopes — no Riverpod/Bloc (consistent, testable).
- **Duplication:** Client + server compatibility engines; multiple discovery repository implementations.
- **Giant files:** `chat_widgets.dart` (~730 lines), `discovery_controller.dart` (~570), `relationship_question_card.dart` (~546).

## 3. Firebase problems

- **Discovery:** Client uses Cloud Functions only (good). CF `getDiscoveryCandidates` does O(n) reads per fetch (likes, passed, block checks per candidate).
- **Chat:** Realtime listeners with `limit(30)` — reasonable; ack-on-every-snapshot may amplify writes.
- **Profile:** Single `saveProfile` on edit (good). Photo ops save per action (expected).
- **No unbounded client Firestore queries** found in presentation layer.

## 4. Discover problems

- No cursor tracking in controller state.
- No background prefetch when stack runs low.
- Full-page `setState` on every drag pixel via discovery page listener.
- Prefetch only top 3 stack photos (good) but full-resolution.

## 5. Image problems

- `MevoraNetworkImages` → raw `NetworkImage` / `Image.network` — memory cache only, no disk cache package.
- Demo assets handled well via `MevoraPhotoImages`.
- Profile model has `thumbUrl`; discovery parsing did not prefer it.

## 6. Compatibility problems

- Server computes breakdown in discovery response (correct for cost).
- Client `MevoraCompatibilityEngine` used for hidden insight + local/mock paths.
- Session cache scaffold unused for breakdown reuse.

## 7. Chat problems

- See §1 (rebuild + scroll leak).
- Pagination for older messages implemented (`loadOlder`) — good.

## 8. State management problems

- Feature-scoped controllers (good).
- Some pages own controllers in `didChangeDependencies` (discovery, chat, music) — consistent pattern.
- Missing `_closed` guard on some controllers (low risk).

## 9. Memory problems

- Most `StreamSubscription`s cancelled in `dispose`.
- Issues listed in §1 (scroll listener, image prefetch listeners).
- `_prefetched` Set grows unbounded per session (low severity).

## 10. Network problems

- One CF call per swipe decision (by design).
- Redundant discovery CF calls when pagination not used.

## 11. Fixes applied (FAZ 1–12)

| Fix | Files | Area |
|-----|-------|------|
| Discovery cursor pagination + low-stack prefetch (`_nextCursor`, limit 15, threshold 3) | `discovery_controller.dart` | Discover / Firebase |
| Empty deck uses cursor before full CF refetch | `discovery_controller.dart` | Discover |
| Prefer `thumbUrl` over `downloadUrl` in candidate parse | `discovery_repository_impl.dart` | Images |
| Image prefetch removes `ImageStreamListener` after load/error | `discovery_network_image.dart` | Memory |
| Chat message list precomputes reversed order once per build | `chat_page.dart` | Chat |
| Scroll listener removed in `dispose` | `chat_page.dart` | Memory |
| `CompatibilitySessionCache` wired via `breakdownFor()` | `discovery_controller.dart`, `discovery_page.dart` | Compatibility |
| Relationship answers via `RelationshipRepository.getSavedAnswers` | relationship data layer, profile pages | Architecture |
| Documentation | `docs/ARCHITECTURE.md`, `docs/PERFORMANCE_AUDIT.md` | Docs |
| Unit test for pagination append | `discovery_controller_test.dart` | Tests |

## 12. Remaining issues

- CF `getDiscoveryCandidates` cost at scale (server-side batching/caching).
- No disk image cache library (add only if product approves dependency).
- Chat selective rebuild (split widgets / `ListenableBuilder` scopes).
- Wire `CompatibilitySessionCache` for breakdown sheets or remove field.
- `getDiscoveryCandidates` block-check batching in Cloud Functions.

## 13. Future improvements

- Server: cache likes/passed IDs, batch `isBlocked` reads.
- Client: `precacheImage` with context for next card in stack.
- Chat: message list `ListView` with `findChildIndexCallback` + stable keys.
- Optional: `cached_network_image` for disk cache.
- Performance profiling (DevTools) on low-end Android devices.
