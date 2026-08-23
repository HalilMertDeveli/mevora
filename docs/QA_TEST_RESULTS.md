# Mevora QA Test Results

Audit date: 2026-08-23  
Auditor role: Senior QA / Mobile QA / Code Auditor  
**No code modified during this audit.**

---

## Overall Result

| Metric | Count |
|--------|------:|
| **Automated test cases executed** | 536 |
| **PASS** | 529 |
| **FAIL** | 7 |
| **BLOCKED** | 0 |
| **NOT TESTABLE (this session)** | ~85 manual/device scenarios |

| Static analysis | Result |
|-----------------|--------|
| `flutter doctor` | PASS (0 issues) |
| `flutter pub get` | PASS |
| `flutter analyze` | PASS WITH WARNINGS (28 info/warnings, 0 errors) |
| Security rules tests (`test/security/`) | PASS (33/33) |
| Integration tests | **NOT RUN** (requires device + production Firebase bootstrap) |
| Golden tests | **N/A** (none in repo) |

---

## Feature Results

| Feature | Status | Bugs | Notes |
|---------|--------|------|-------|
| **Build / Toolchain** | PASS | 0 | Flutter 3.41.9, Android SDK 36, emulator available |
| **Static Analysis** | PASS WITH WARNINGS | 0 | 28 info-level items (const, deprecated Radio) |
| **Authentication** | PASS WITH WARNINGS | 2 | 529-7 failures include 2 phone UI tests; core auth unit tests pass |
| **Registration** | PASS | 0 | Register validation widget tests pass |
| **Age 18+** | PASS | 0 | `onboarding_validators_test.dart` covers 17/18 edge cases |
| **Onboarding** | PASS | 0 | Flow + photo upload tests pass |
| **Profile** | CODE PRESENT | 0 | Profile tab tests limited; edit profile has settings tests |
| **Profile Edit** | PASS WITH WARNINGS | 0 | Settings/edit tests pass; full E2E save→discover not device-tested |
| **Photo Upload** | PASS | 0 | Moderation pipeline + storage rules tests pass |
| **Discover** | PASS WITH WARNINGS | 1 | Swipe/controller tests pass; 1 widget test stale |
| **Swipe** | PASS | 0 | `discovery_swipe_test.dart` 5/5 after recent badge format update |
| **Compatibility Engine** | PASS WITH WARNINGS | 1 | Resolver tests 10/10; 1 hidden-insight unit test fails (test drift) |
| **Why You Match** | CODE PRESENT | 0 | Breakdown mapper + reason engine unit tested; device tap not run |
| **Matching Engine** | PASS | 0 | `relationship_matching_test`, discovery decision tests pass |
| **Questions (Relationship)** | PASS WITH WARNINGS | 2 | Core flow tests pass; 2 offer-card copy tests fail (stale expectations) |
| **Chat** | PASS | 0 | Messaging, policy, pagination unit tests pass |
| **Notifications** | NOT TESTABLE | 0 | FCM requires physical device + push infra |
| **Verification (Sumsub)** | NOT TESTABLE | 0 | Widget/status tests pass; SDK E2E needs credentials |
| **Payments (Boost IAP)** | NOT TESTABLE | 0 | UI + repository unit tests pass; real purchase needs sandbox |
| **Settings** | PASS WITH WARNINGS | 1 | Logout tests pass; **delete account UI missing from router** |
| **Account Deletion** | **FAIL** | 1 | Backend implemented; UI unreachable (P1) |
| **Block** | PASS | 0 | Safety compliance + CF `blockUser` present |
| **Report** | CODE PRESENT | 0 | Report page routed; full submit not device-tested |
| **Localization** | PASS WITH WARNINGS | 0 | TR/EN widget tests pass; relationship tests use old hardcoded EN |
| **Theme** | PASS | 0 | Dark theme swipe test passes |
| **Animations** | PASS | 0 | Animation duration + Rive fallback tests pass |
| **Navigation** | PASS WITH WARNINGS | 1 | go_router coverage good; orphan `AccountSettingsPage` |
| **Firebase (client)** | PASS WITH WARNINGS | 0 | No Firestore in presentation widgets |
| **Firestore Security** | PASS | 0 | 33 automated rule contract tests |
| **Storage Security** | PASS | 0 | Owner-only pending uploads enforced |
| **Cloud Functions** | **FAIL** | 1 | `spotifyMusic.ts` functions **not exported** from `index.ts` |
| **Error Handling** | PASS WITH WARNINGS | 0 | `Failure`/`Result` pattern; localized auth errors tested |
| **Loading States** | CODE PRESENT | 0 | Loading widgets tested; not every screen audited on device |
| **Empty States** | PASS | 0 | Discovery empty/seen-everyone widget tests pass |
| **Network Failure** | NOT TESTABLE | 0 | Requires device network simulation |
| **Offline** | NOT TESTABLE | 0 | No offline-mode test suite |
| **Performance** | CODE PRESENT | 0 | Prior audit fixes verified in code; no DevTools run |
| **Memory** | PASS WITH WARNINGS | 0 | Chat scroll listener dispose confirmed in code |
| **Security (secrets)** | PASS | 0 | Public Firebase API keys only; Spotify secrets denied in rules |
| **Music / Spotify** | **FAIL** | 1 | Music UI tests mostly pass; CF deployment gap |
| **Data Consistency** | CODE PRESENT | 0 | Server-authoritative fields protected in rules |
| **Production Readiness** | **NOT READY** | — | See `QA_PRODUCTION_READINESS.md` |

---

## Automated Test Failures (7)

| Test file | Test name | Likely cause |
|-----------|-----------|--------------|
| `phone_auth_screens_test.dart` | invalid phone shows Turkish error | Test harness missing `PhoneAuthController` in `AuthScope` |
| `auth_pages_test.dart` | phone entry empty number | Same harness gap |
| `compatibility_engine_v2_test.dart` | hidden compatibility requires aligned answers | Test missing `compatibilityStatus: ready` after API change |
| `discovery_widgets_test.dart` | discovery card compatibility | Test missing `CompatibilityDisplayStatus.ready` |
| `relationship_prompt_test.dart` | offer card copy (×2) | Hardcoded old copy; UI uses `relationshipTestHeadline` |
| `music_page_test.dart` | profile details music badge | Expects old `78%` chip; UI now uses `CompatibilityDiscoverBadge` |

---

## Security Test Execution

```
test/security/ — 33/33 PASS
```

Covers: Firestore production rules, storage rules, location rules, photo moderation, discovery coordinate isolation, smoke user rules, production compliance checklist.

---

## Integration Test Status

| File | Status |
|------|--------|
| `integration_test/smoke/app_launch_test.dart` | **NOT RUN** — calls `bootstrap(AppEnvironment.production)` |
| `integration_test/readme_screenshots_test.dart` | **NOT RUN** |

**Reason:** Requires configured Firebase on target device; not executed in this audit to avoid production data mutation.

---

## Manual / Device Matrix (NOT TESTABLE this session)

| Area | Reason |
|------|--------|
| Google / Apple / Phone live auth | No dedicated test accounts configured |
| Sumsub liveness verification | `SUMSUB_*` secrets + physical device |
| Boost IAP purchase | Play/App Store sandbox accounts |
| FCM push delivery | APNS/FCM device + backend |
| Full Register→Onboarding→Discover E2E | Requires Firebase project + test users |
| Network offline simulation | Not run on emulator |
| Performance profiling (60 FPS) | DevTools not run |

---

## Dependency Audit (`pubspec.yaml`)

| Finding | Severity |
|---------|----------|
| 39 packages have newer incompatible versions | P4 INFO |
| No unused dependencies identified in audit | — |
| No version conflicts on `pub get` | — |
| Notable: `livekit_client`, `flutter_idensic_mobile_sdk_plugin`, `in_app_purchase` increase attack surface | INFO |

---

## Evidence Artifacts

- Full test log: `flutter test` → 529 pass, 7 fail (2026-08-23)
- Analyzer: 28 issues, 0 errors
- `flutter doctor -v`: all green, emulator `emulator-5554` available
- Code paths reviewed: `app_router.dart`, `firestore.rules`, `functions/src/index.ts`, `account_settings_page.dart`
