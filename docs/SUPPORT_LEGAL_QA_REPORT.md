# SUPPORT & LEGAL QA REPORT

**Date:** 2026-08-23  
**Scope:** Support center, FAQ, tickets, legal docs, account deletion, report/block, Firebase rules, localization

---

## Results

| Area | Result | Notes |
|------|--------|-------|
| Support | **PASS** | Native Help & Support Center at Settings → Help & Support |
| FAQ | **PASS** | 10 questions, categories, search, in-app expandable answers |
| Community Rules | **PASS** | Native screen with 14 sections + report linkage |
| Terms of Use | **PASS** | Native screen, 16 sections, TR/EN |
| Privacy Policy | **PASS** | Native screen + public web page for Play Store URL |
| Account Deletion | **PASS** | Settings → Account → Delete Account + CF `deleteUserAccount` |
| Report User | **PASS** | CF + Firestore; success snackbar + error handling added |
| Block User | **PASS** | Existing implementation verified |
| Firebase Security | **PASS** | `supportTickets` rules + storage path + index + deletion |
| Turkish Localization | **PASS** | All new strings in `app_tr.arb` |
| English Localization | **PASS** | All new strings in `app_en.arb` |
| Android Release Build | **NOT RUN** | Requires local release build on device/CI |
| Google Play Compliance Risks | See below |

---

## Google Play Compliance Risks (Manual Steps Remaining)

1. **Deploy Firebase Hosting** — Run `firebase deploy --only hosting` so `https://mevora-d6ed0.web.app/privacy` is live for Play Console Privacy Policy URL.
2. **Custom domain (optional)** — Point `mevora.app` DNS to Firebase Hosting if you prefer branded URLs.
3. **Deploy Firestore rules + indexes** — `firebase deploy --only firestore` for `supportTickets`.
4. **Deploy Cloud Function** — `deleteUserAccount` update includes support ticket cleanup.
5. **Play Console Data Safety form** — Align declarations with in-app Privacy Policy sections.
6. **Release build smoke test** — Verify support ticket create/list on physical Android device.

---

## What Was Fixed

| Problem | Fix |
|---------|-----|
| Help/Terms/Privacy opened parked `mevora.app` URLs | Native in-app screens + Firebase Hosting static pages |
| No FAQ | Full FAQ with search and categories |
| No support tickets | `supportTickets` collection + form + list UI |
| Delete account buried | Dedicated destructive tile in Settings |
| Report success silent | `reportThanks` snackbar + error handling |
| Legal pages blocked when logged out | Public routes `/legal/terms`, `/legal/privacy`, `/legal/guidelines` |

---

## Automated Tests

- `test/features/support/support_content_test.dart` — PASS
- `test/security/` — 34/34 PASS (includes supportTickets rules contract)
- `test/features/safety/` — PASS
- `test/features/authentication/account_settings_page_test.dart` — PASS
