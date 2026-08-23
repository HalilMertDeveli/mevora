# Mevora QA Bug Report

Audit date: 2026-08-23  
**Status: Confirmed bugs documented — NOT fixed during audit.**

---

## Summary

| Severity | Count |
|----------|------:|
| **P0 — Critical** | 0 |
| **P1 — High** | 2 |
| **P2 — Medium** | 4 |
| **P3 — Low** | 5 |
| **P4 — Info** | 3 |

---

## P1 — High

### MEV-QA-001

**TITLE:** Account deletion UI unreachable from Settings  
**CATEGORY:** Account Deletion / Navigation / Compliance  
**SEVERITY:** P1 — HIGH  
**STATUS:** Confirmed  

**LOCATION:**  
- `lib/features/authentication/presentation/pages/account_settings_page.dart`  
- `lib/core/routing/app_router.dart` (page not registered)  
- `lib/features/settings/presentation/pages/settings_page.dart` (no delete entry)

**SCREEN:** Settings → Account (expected)  

**STEPS TO REPRODUCE:**  
1. Sign in and complete onboarding.  
2. Open Settings (`/settings`).  
3. Search for "Delete account" / "Hesabı sil".  

**EXPECTED:** User can initiate account deletion with confirmation dialog.  

**ACTUAL:** `AccountSettingsPage` exists with delete flow wired to `AuthController.deleteAccount()` and CF `deleteUserAccount`, but page is **not in go_router** and not linked from Settings. Only logout is available.  

**EVIDENCE:** Grep shows `AccountSettingsPage` only referenced in its own file + localization docs. `deleteUserAccount` CF exists in `functions/src/deleteAccount.ts`.  

**ROOT CAUSE:** Orphan screen — implementation complete, navigation never wired.  

**AFFECTED SYSTEM:** Auth, GDPR/privacy compliance, account lifecycle  

**USER IMPACT:** Users cannot self-delete accounts from the app despite backend support.  

**RECOMMENDED FIX:** Add route `/settings/account` or delete button on `SettingsPage` → existing `AccountSettingsPage` / deletion dialog.  

---

### MEV-QA-002

**TITLE:** Spotify Music Cloud Functions not deployed via `index.ts`  
**CATEGORY:** Firebase / Cloud Functions / Music  
**SEVERITY:** P1 — HIGH  
**STATUS:** Confirmed  

**LOCATION:**  
- `functions/src/spotifyMusic.ts` (functions defined)  
- `functions/src/index.ts` (missing exports)

**SCREEN:** Music tab, Spotify link, music compatibility  

**STEPS TO REPRODUCE:**  
1. Deploy Cloud Functions from current `index.ts`.  
2. In app, attempt Spotify music link / sync / disconnect.  

**EXPECTED:** `spotifyLinkMusic`, `getMusicAccount`, `syncSpotifyTaste`, etc. callable.  

**ACTUAL:** `functions/src/index.ts` exports `spotifyCompleteAuth` only — **no exports from `spotifyMusic.ts`**. Music features will fail at runtime in production.  

**EVIDENCE:**  
```typescript
// functions/src/index.ts — spotifyMusic NOT exported
export {spotifyCompleteAuth} from "./spotifyAuth";
```

**ROOT CAUSE:** Missing export registration.  

**AFFECTED SYSTEM:** Music tab, music compatibility scoring, Spotify taste sync  

**USER IMPACT:** Music features broken in production after deploy.  

**RECOMMENDED FIX:** Add `export * from "./spotifyMusic"` or explicit exports to `index.ts`; verify deployed function list.  

---

## P2 — Medium

### MEV-QA-003

**TITLE:** Seven automated tests failing in CI suite  
**CATEGORY:** Regression / Test Quality  
**SEVERITY:** P2 — MEDIUM  
**STATUS:** Confirmed  

**LOCATION:** See `QA_TEST_RESULTS.md` failure table  

**EXPECTED:** `flutter test` → 536/536 pass  

**ACTUAL:** 529 pass, 7 fail  

**USER IMPACT:** Regression signal degraded; real bugs may ship unnoticed.  

**RECOMMENDED FIX:** Update tests for l10n/compatibility API changes; fix phone auth test harness.  

---

### MEV-QA-004

**TITLE:** Linked accounts management unreachable  
**CATEGORY:** Authentication / Settings  
**SEVERITY:** P2 — MEDIUM  
**STATUS:** Confirmed  

**LOCATION:** `account_settings_page.dart` L46–90  

**EXPECTED:** User can link Google/Apple/Spotify/email from settings.  

**ACTUAL:** Same orphan page as delete account — not routed.  

**USER IMPACT:** Cannot manage linked providers in production UI.  

---

### MEV-QA-005

**TITLE:** Phone empty-number validation not verified in widget tests  
**CATEGORY:** Authentication / Phone  
**SEVERITY:** P2 — MEDIUM  
**STATUS:** Suspected (test harness)  

**LOCATION:**  
- `test/features/authentication/auth_pages_test.dart` L282  
- `test/features/authentication/phone_auth_screens_test.dart` L117  

**EXPECTED:** Tap "Send code" with empty phone → `authInvalidPhone` shown.  

**ACTUAL:** Test fails — `PhoneLoginScreen` requires `AuthScope.phoneAuth` not provided in test `_wrap()`.  

**USER IMPACT:** Unknown in production — **FUNCTIONALLY NOT VERIFIED** in automated suite. Code path exists in `PhoneAuthController`.  

**RECOMMENDED FIX:** Fix test harness; manually verify on device.  

---

### MEV-QA-006

**TITLE:** Profile details opened via Navigator.push — not deep-linkable  
**CATEGORY:** Navigation  
**SEVERITY:** P2 — MEDIUM  
**STATUS:** Confirmed  

**LOCATION:** `discovery_page.dart` L390–399  

**EXPECTED:** Profile details shareable / deep-linkable (optional product requirement).  

**ACTUAL:** `Navigator.push` bypasses go_router.  

**USER IMPACT:** Back stack inconsistencies; no URL route for profile preview.  

---

## P3 — Low

### MEV-QA-007

**TITLE:** Relationship offer card tests use obsolete hardcoded copy  
**CATEGORY:** Localization / Tests  
**SEVERITY:** P3 — LOW  
**STATUS:** Confirmed (test drift)  

**LOCATION:** `relationship_prompt_test.dart` L292 — expects `"We haven't found a match for you yet."`  

**ACTUAL UI:** `RelationshipTestOfferCard` uses `l10n.relationshipTestHeadline` → `"Discover people who share your views"`.  

**USER IMPACT:** None if UI is correct — **product copy updated, tests stale**.  

---

### MEV-QA-008

**TITLE:** Discovery widget test expects compatibility without `ready` status  
**CATEGORY:** Compatibility / Tests  
**SEVERITY:** P3 — LOW  
**STATUS:** Confirmed (test drift)  

**LOCATION:** `discovery_widgets_test.dart` L59–69  

**ACTUAL:** `CompatibilityDiscoverBadge` hidden unless `CompatibilityDisplayStatus.ready`.  

---

### MEV-QA-009

**TITLE:** Music profile details test expects legacy compatibility chip format  
**CATEGORY:** Music / Tests  
**SEVERITY:** P3 — LOW  
**STATUS:** Confirmed (test drift)  

**LOCATION:** `music_page_test.dart` L77 — expects `find.textContaining('78%')`  

**ACTUAL:** Details page uses `CompatibilityDiscoverBadge` with status gating.  

---

### MEV-QA-010

**TITLE:** Hidden compatibility unit test missing `compatibilityStatus`  
**CATEGORY:** Compatibility / Tests  
**SEVERITY:** P3 — LOW  
**STATUS:** Confirmed (test drift)  

**LOCATION:** `compatibility_engine_v2_test.dart` L81–90  

**ACTUAL:** `hasCompatibilityScore` requires `compatibilityStatus == ready`.  

---

### MEV-QA-011

**TITLE:** Legacy auth pages not routed  
**CATEGORY:** Dead Code  
**SEVERITY:** P3 — LOW  
**STATUS:** Confirmed  

**LOCATION:** `phone_sign_in_page.dart`, `otp_verification_page.dart` — superseded by `PhoneLoginScreen` / `OtpVerificationScreen`.  

**USER IMPACT:** None (unreachable). Maintenance burden.  

---

## P4 — Info

### MEV-QA-012

**TITLE:** No golden / screenshot regression tests  
**CATEGORY:** Test Infrastructure  
**SEVERITY:** P4 — INFO  

**EVIDENCE:** Zero `matchesGoldenFile` in `test/`.  

---

### MEV-QA-013

**TITLE:** 39 dependencies have newer incompatible versions  
**CATEGORY:** Dependencies  
**SEVERITY:** P4 — INFO  

**EVIDENCE:** `flutter pub get` advisory output.  

---

### MEV-QA-014

**TITLE:** Sumsub applicant delete API stubbed  
**CATEGORY:** Verification / Backend  
**SEVERITY:** P4 — INFO  

**LOCATION:** `functions/src/sumsub/sumsubApplicantLifecycle.ts` — `TODO(sumsub-activation)`  

**USER IMPACT:** Account deletion may not remove Sumsub applicant data until implemented.  

---

## Suspected / Not Reproduced (Monitoring)

| ID | Note |
|----|------|
| — | Chat broad `AnimatedBuilder` rebuild — performance concern, not functional bug |
| — | CF `getDiscoveryCandidates` cost at scale — performance/cost, not correctness |
| — | Fake compatibility reasons — **not found**; `CompatibilityReasonEngine` uses real data |

---

## Security Findings

**No P0 security vulnerabilities confirmed** in automated rules tests.  
Client does not write server-authoritative fields (likes, purchases, verification) per `firestore.rules`.  
Public Firebase API keys present in `firebase_options.dart` — **expected** for client SDK.

**NOT TESTABLE:** Live penetration test against production Firebase project.
