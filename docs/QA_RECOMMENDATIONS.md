# Mevora QA Recommendations

Audit date: 2026-08-23  
Prioritized by: **Impact × Severity ÷ Effort**

---

## TOP 10 Priority Fixes

### 1. Wire Account Deletion to Settings (P1 — Low effort, High impact)
**What:** Register `AccountSettingsPage` in `app_router.dart` OR add "Delete account" to `SettingsPage`.  
**Why:** Backend `deleteUserAccount` CF is complete; users cannot self-delete — compliance blocker.  
**Effort:** ~2–4 hours  
**Verify:** Settings → Delete → confirm → auth signed out → Firestore user removed.

---

### 2. Export Spotify Music Cloud Functions (P1 — Low effort, High impact)
**What:** Add exports from `functions/src/spotifyMusic.ts` to `functions/src/index.ts`; redeploy.  
**Why:** Music link, sync, compatibility, and disconnect will 404 in production.  
**Effort:** ~1 hour + deploy  
**Verify:** `firebase functions:list` includes `spotifyLinkMusic`, `getMusicAccount`, etc.

---

### 3. Fix 7 Failing Automated Tests (P2 — Medium effort, High impact)
**What:**  
- Update relationship/discovery/music tests for l10n + `CompatibilityDisplayStatus`  
- Fix phone auth test harness to provide `AuthScope.phoneAuth`  
- Update hidden compatibility test with `compatibilityStatus: ready`  
**Why:** CI regression gate is broken; 1.3% failure rate masks real issues.  
**Effort:** ~4–6 hours  
**Verify:** `flutter test` → 536/536 pass.

---

### 4. Dedicated Staging QA Test Accounts (P1 process — Medium effort)
**What:** Create 2+ Firebase test users with complete profiles, opposing preferences, relationship answers.  
**Why:** Compatibility, matching, chat, block flows cannot be E2E verified without real pairs.  
**Effort:** ~2 hours setup  
**Verify:** Manual script in `docs/SMOKE_TEST.md`.

---

### 5. Run Integration Test on Emulator (P2 — Low effort)
**What:** `flutter test integration_test/smoke/app_launch_test.dart -d emulator-5554` against staging config.  
**Why:** Only test validating full `bootstrap(production)` path; never executed in audit.  
**Effort:** ~1 hour  
**Verify:** App boots without crash.

---

### 6. Device QA: Auth Matrix (P2 — Medium effort)
**What:** Manual test Google, email, phone OTP on Android emulator with staging Firebase.  
**Why:** Phone widget tests fail; production phone flow **NOT FUNCTIONALLY VERIFIED**.  
**Effort:** ~4 hours  
**Verify:** Login → profile created → logout → re-login.

---

### 7. Device QA: Discover → Match → Chat E2E (P2 — Medium effort)
**What:** Two test accounts swipe mutually; verify match UI, chat opens, messages sync.  
**Why:** Core product loop; only partially covered by unit tests.  
**Effort:** ~3 hours  
**Verify:** Match celebration → chat message delivered realtime.

---

### 8. Sumsub Sandbox Verification (P2 — High effort, credentials required)
**What:** Configure `SUMSUB_*` secrets; test full verify flow on physical device.  
**Why:** Verification is production feature; only widget/unit tests pass.  
**Effort:** ~1 day (setup + test)  
**Verify:** Badge appears; `users/{uid}.isVerified` set via webhook.

---

### 9. IAP Boost Sandbox Purchase (P2 — High effort)
**What:** Configure Play Console / App Store Connect products; test `verifyBoostPurchase` on device.  
**Why:** Revenue feature; client-only tests insufficient.  
**Effort:** ~1 day  
**Verify:** Boost active in discover; expires correctly.

---

### 10. Add Golden Tests for Critical UI (P4 — Medium effort, long-term)
**What:** Golden tests for Discover card, compatibility badge, chat bubble, settings.  
**Why:** Zero visual regression coverage today.  
**Effort:** ~2–3 days  
**Verify:** `matchesGoldenFile` in CI.

---

## Additional Recommendations

### Test Infrastructure
- Add CI job: `flutter test` + `test/security/` on every PR
- Add phone auth widget harness fixture shared across auth tests
- Mark integration tests with `@Tags(['integration'])` for selective CI

### Navigation / UX
- Wire linked accounts page or merge into Settings
- Consider go_router route for `DiscoveryProfileDetailsPage`
- Remove dead `phone_sign_in_page.dart`, `discovery_placeholder_page.dart`

### Firebase / Backend
- Document deployed function manifest vs client `BackendCallable` invocations
- Complete Sumsub applicant delete on account deletion
- Add CF integration tests in emulator where possible

### Performance
- Run Flutter DevTools on Discover swipe + Chat scroll on low-end Android
- Monitor `getDiscoveryCandidates` CF cost in staging with realistic user count

### Security
- Periodic rules audit when new collections added
- Ensure `TEST ACCOUNT REQUIRED` label on any smoke scripts touching production

### Localization
- Audit tests to use `AppLocalizations` lookups, not hardcoded English
- Add CI check for missing ARB keys between EN/TR

---

## Fix Phase Order (Post-Audit)

```
Phase 1 (Release blockers):  #1, #2, #3
Phase 2 (E2E confidence):   #4, #5, #6, #7
Phase 3 (Monetization):     #8, #9
Phase 4 (Quality debt):     #10, dead code cleanup
```

---

## Estimated Timeline to READY WITH WARNINGS

| Phase | Duration |
|-------|----------|
| P1 code fixes | 1–2 days |
| Test suite green | 0.5 day |
| Staging E2E (2 accounts) | 1–2 days |
| Sumsub + IAP (if launch-required) | 3–5 days |

**Minimum to NOT READY → READY WITH WARNINGS:** Fix #1, #2, #3 + basic E2E (#6, #7) ≈ **3–5 engineering days**.
