# Production go-live checklist (Faz 5)

Complete Faz 1–4 code first, then this list before store release.

## Project identity

- [ ] Confirm which Firebase project ships in production builds
  - Flutter `AppConfig.firebaseProjectId` production → `mevora-production`
  - Current default options / hosting often point at `mevora-d6ed0`
  - Align flavors, `google-services.json`, iOS plist, Hosting, Functions
- [ ] Store listing privacy URL → deployed Hosting `/privacy`
- [ ] Terms URL → `/terms`

## Security

- [ ] Deploy Firestore rules + indexes + Storage rules
- [ ] App Check **enforced** in production (Play Integrity / App Attest)
- [ ] No App Check debug tokens in prod
- [ ] First admin claim via `setAdminClaim.mjs` on a dedicated ops account
- [ ] Verify non-admin cannot call `adminGetDashboard`

## Ops

- [ ] Deploy Functions (incl. automation + admin callables)
- [ ] Deploy Hosting (`/admin` + legal pages)
- [ ] Cloud Tasks / Scheduler jobs visible in Console
- [ ] Smoke: report → review queue; suspend; photo MR list; ban with `BAN` confirm
- [ ] Orphan Storage cleanup: dry-run first, review candidates, then live

## Privacy (KVKK)

- [ ] In-app **Verilerimi indir** works on a real device
- [ ] Account deletion completes; run `adminVerifyDeletion`
- [ ] Privacy policy text matches hard-delete + match-shell anonymization model
- [ ] Sumsub credentials live only if KYC is on; applicant delete tested in sandbox

## Mobile regression (must not break)

- [ ] Login / signup / onboarding
- [ ] Discovery swipe + match
- [ ] Chat text / image / voice
- [ ] Block + report
- [ ] Incoming likes gate (free vs premium)
- [ ] Account delete
- [ ] Suspended / banned account cannot enter discovery (force sign-out)

## Monitoring

- [ ] Crashlytics enabled on production
- [ ] `health` callable returns `signals`
- [ ] Alert path for `automationJobs` status=`failed` (Console or log-based)

## Automated tests (CI / local)

```bash
cd functions && npm test
flutter gen-l10n
flutter test test/security/ test/features/authentication/user_document_test.dart
flutter analyze lib/core/identity lib/bootstrap.dart lib/features/authentication lib/features/settings/data
```
