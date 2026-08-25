# Production deploy checklist (Faz 1)

Ops-only. Does not change dating app features.

## Before deploy

1. Confirm Firebase project (`mevora-d6ed0` vs any `mevora-production` flavor) matches store builds.
2. Ensure Blaze plan if using Cloud Tasks / scheduled functions.
3. Secrets present: LiveKit, Spotify, Sumsub (optional until KYC live), App Check.

## Deploy order

```bash
# From repo root
firebase deploy --only firestore:rules,firestore:indexes
firebase deploy --only functions
firebase deploy --only hosting
firebase deploy --only storage
```

Wait for index build completion in Console before relying on new queries.

## First admin

```bash
# Never use a consumer dating account as the long-term admin identity.
GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa.json \
  node functions/scripts/setAdminClaim.mjs <ADMIN_UID>
```

Admin must sign out/in (or force token refresh) then open `/admin`.

## Smoke after deploy

- [ ] `health` callable returns ok
- [ ] Non-admin cannot call `adminGetDashboard` (permission-denied)
- [ ] Admin dashboard loads metrics
- [ ] Create a test report → appears in `adminReviewQueue`
- [ ] Mobile login / discovery still works (no callable rename)

## Rollback

Redeploy previous functions revision; rules can be reverted via git. Hosting `/admin` can stay — it does not affect the mobile binary.
