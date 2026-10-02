# Mevora — Google Play production launch

The single operating guide for taking Mevora to Google Play. Everything else is a
reference this document points to.

- **Status of this document:** written 2026-10-01 from an audit of the repository at
  `main` = `preview` = `7565ebda`, plus the launch-preparation changes listed in §9.
- **What it covers:** what is done in the repository, and what only the owner can do — in
  the order to do it.
- **What it is not:** it is not the *Final Production Acceptance* gate, not legal advice,
  and not approval to merge `preview` into `main`, deploy, or submit. Those stay owner
  decisions (`CLAUDE.md`, "Approval gate").

Quick self-check at any time:

```bash
node tool/productionReadiness.cjs --online
```

It prints `PASS` / `FAIL` / `BLOCKED` / `NOT TESTABLE` per item. `FAIL` means the
repository is wrong. `BLOCKED` means the repository is ready and the item waits on a step
in §2.

---

## 1. Decision zero — which Firebase project is production?

**This has to be decided before anything else.** The audit found that the production
build and the deployed backend are two different projects:

| | `mevora-production` | `mevora-d6ed0` |
|---|---|---|
| What the **production flavor** of the app talks to | **yes** (`lib/core/config/firebase/firebase_options_resolver.dart`, `android/app/src/production/google-services.json`) | no — this is the *development* flavor |
| Cloud Functions deployed (read 2026-10-01) | **0** | 78 |
| Firestore database | exists; deployed rules not verified | exists, holds the test accounts |
| Secrets, Didit webhook, Spotify, admin console, hosted policy pages | none | all of it |
| Cloud Billing account | linked, **closed** | linked, **closed** |
| Registered SHA fingerprints | 2 (the same debug-keystore pair as development) | 2 |

So a production build made today would start against a project with no backend.

**Option A — make `mevora-production` the real production (recommended).**
The code is already wired this way. Production starts clean: no test accounts, no sandbox
verification, no orphaned functions. Cost: everything in §2 steps 3–9 has to be set up on
that project once — rules, indexes, functions, secrets, Didit (live), hosting, App Check.

**Option B — declare `mevora-d6ed0` production.**
Nothing to provision, but: it holds the test accounts and sandbox-verified badges, it has
twelve deployed functions that no branch contains (`docs/DEPLOY_NOTES.md`), development
builds would keep writing to the production database, and the production flavor must be
repointed (Dart options, `google-services.json`, `AppConfig.firebaseProjectId`,
`.firebaserc`) — a code change that needs its own branch and review.

The rest of this document says **`<prod>`** for whichever project is chosen and
**`<site>`** for its Hosting URL (`https://<prod>.web.app` until a custom domain exists).

---

## 2. Owner actions, in order

Each step: **where**, **what**, **expected result**, **how to verify**. Do them in this
order — later steps depend on earlier ones. Nothing here can be done by an agent.

### Step 1 — Decide the production project
- **Where:** this document, §1.
- **Action:** choose Option A or B and say so.
- **Expected:** one project is "production" in every sentence that follows.
- **Verify:** `node tool/productionReadiness.cjs` → "production project is consistent" stays `PASS`.

### Step 2 — Open Cloud Billing
- **Where:** Google Cloud Console → Billing.
- **Action:** reopen the billing account (or link `<prod>` to an open one). A financial
  action — owner only. Details: `docs/PUBLISH_BLOCKERS.md` item 1.
- **Expected:** Cloud Functions can be deployed and run; phone sign-in can send SMS.
- **Verify:** `node tool/productionReadiness.cjs --online` → "cloud billing" is `PASS`.

### Step 3 — Create the Google Play developer account and the app
- **Where:** play.google.com/console.
- **Action:** create the developer account (identity verification; a personal account
  shows your legal name, an organization account needs a D-U-N-S number), then create the
  app `com.mevora.app`, default language Turkish, app, free.
- **Expected:** the package name is registered to you; Play App Signing is on.
- **Verify:** Play Console → Test and release → Setup → App signing shows an **app
  signing key certificate**.
- **Note:** a personal account created after 13 Nov 2023 must run a **closed test with
  at least 12 testers opted in for 14 consecutive days** before it may apply for
  production (step 16).

### Step 4 — Create the upload key
- **Where:** your own machine. `docs/ANDROID_RELEASE_SIGNING.md`.
- **Action:** `keytool -genkeypair …`, store the `.jks` and passwords in a password
  manager and an offline backup, write `android/key.properties`.
- **Expected:** `flutter build appbundle --flavor production -t lib/main_production.dart --release` produces a signed bundle.
- **Verify:** `node tool/productionReadiness.cjs` → "release signing material" is `PASS`.

### Step 5 — Upload a first bundle to Internal testing
- **Where:** Play Console → Test and release → Testing → Internal testing.
- **Action:** upload the bundle from step 4. This is what makes Google generate the app
  signing key. (It needs steps 6–9 to *work*; uploading it early is only to obtain the
  fingerprints.)
- **Expected:** the App signing page lists SHA-1 and SHA-256 for both keys.
- **Verify:** both fingerprints are visible.

### Step 6 — Register the fingerprints in Firebase
- **Where:** Firebase console → `<prod>` → Project settings → Android app `com.mevora.app`.
- **Action:** add SHA-1 **and** SHA-256 of the **app signing key** and of the **upload
  key**. Download the new `google-services.json` and hand it over so it can replace
  `android/app/src/production/google-services.json` (through a branch and PR).
- **Expected:** the file contains an Android OAuth client with a certificate hash.
- **Verify:** `node tool/productionReadiness.cjs` → "signing certificate in Firebase" is `PASS`.

### Step 7 — Enable sign-in providers and App Check
- **Where:** Firebase console → `<prod>`.
- **Action:**
  1. Authentication → Sign-in method: enable Phone, Email/Password and Google.
  2. App Check → register `com.mevora.app` with **Play Integrity**, using the app signing
     key's SHA-256.
  3. Play Console → Test and release → App integrity → link the Cloud project `<prod>`.
- **Expected:** store-installed builds get App Check tokens; every member-facing callable
  enforces App Check.
- **Verify:** step 14 (device test). There is no way to verify this without a
  Play-distributed build.

### Step 8 — Provider credentials for production
- **Where:** Didit console, Spotify developer dashboard, GIPHY developer dashboard.
- **Action:**
  - **Didit:** a **live** application and workflow, a webhook destination pointing at the
    `identityVerificationWebhook` URL of `<prod>`. Sandbox must never be used on
    production: it answers with canned approvals.
  - **Spotify:** confirm `mevora://auth/spotify` is a registered redirect URI and that the
    app is out of development mode (in development mode only allow-listed accounts can
    connect).
  - **GIPHY:** a production API key for the humor catalogue, and confirm GIPHY's
    attribution terms are met.
- **Expected:** real credentials exist for the production project.
- **Verify:** the values are in your password manager; nothing is committed.

### Step 9 — Secrets, configuration and the first deploy to `<prod>`
- **Where:** a `main` worktree (`D:\Mevora-deploy`), never a task worktree. Only after
  `preview` has been merged into `main` with your approval.
- **Action, in this order:**
  1. Secrets (each: `firebase functions:secrets:set <NAME> --project <prod>`):
     `SPOTIFY_CLIENT_SECRET`, `DIDIT_API_KEY`, `DIDIT_WEBHOOK_SECRET`, `GIPHY_API_KEY`,
     `ADMIN_BFF_SHARED_SECRET`, and `LIVEKIT_*` only if calls are switched on.
     `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` comes from step 11: the four functions that bind
     it (`verifyBoostPurchase`, `verifyPremiumPurchase`, `onPlaySubscriptionNotification`,
     `reconcileVoidedBoostPurchases`) **cannot be deployed until that secret exists** —
     deploy everything else now and those four after step 11. A function that binds a secret which does not exist fails
     the deploy; the same holds for `DIDIT_API_KEY` on the account-deletion functions. `SMOKE_TEST_SECRET` is **not** needed:
     the smoke callables are emulator-only and are not part of a deploy
     (`docs/DEPLOY_NOTES.md` → "Emulator-only callables").
  2. `functions/.env.<prod>` (not committed): `SPOTIFY_CLIENT_ID`, `DIDIT_WORKFLOW_ID`,
     `DIDIT_ENVIRONMENT=live`, `FACE_ANCHOR_ENFORCEMENT=on`,
     `PREMIUM_ANDROID_PACKAGE_NAME=com.mevora.app`, `PREMIUM_ANDROID_PRODUCT_IDS=…`
     (step 11). **Do not** set `DIDIT_ALLOW_SANDBOX_VERIFICATION` on production.
  3. Deploy rules, indexes, functions and hosting. The agent prepares the exact command
     at that time; you run it. On `mevora-d6ed0` never run a bare functions deploy
     (`docs/DEPLOY_NOTES.md`).
  4. Seed the humor catalogue with the admin callable `seedInternalHumorContent` (only if
     humor ships, step 10).
  5. Bootstrap the first owner/staff account (`tool/adminBootstrapStaff.cjs`).
- **Expected:** `<site>/privacy`, `/terms`, `/guidelines`, `/child-safety`,
  `/delete-account`, `/help` all answer 200 with the new Turkish + English pages; the
  functions are listed in the console.
- **Verify:** open the six URLs; `firebase functions:list --project <prod>`.

### Step 10 — Decide what version 1 contains
- **Where:** here.
- **Action:** three switches exist; each is off in a release build unless turned on.

  | Feature | Switch | Before turning it on |
  |---|---|---|
  | Humor | `--dart-define=HUMOR_LAB_ENABLED=true` | Choose the final Humor Core sequence and release it — §6 |
  | Premium | `--dart-define=PREMIUM_ENABLED=true` + `PREMIUM_ANDROID_PRODUCT_IDS` | Step 11 |
  | Photo verification required | `FACE_ANCHOR_ENFORCEMENT=on` (functions) | Live Didit key (step 8) |

- **Expected:** a written list of what the build contains. The store description must
  describe exactly that (`docs/PLAY_STORE_LISTING.md`).
- **Verify:** the build command and the listing text agree.

### Step 11 — Products, the Play Developer API and RTDN
- **Where:** Play Console → Monetize; Google Cloud Console.
- **Action:** see §5 for the exact identifiers.
  1. Create and activate the three Boost one-time products.
  2. Create the Premium subscription and its base plans (only if Premium ships).
  3. Create a service account, invite it in Play Console → Users and permissions with
     *View financial data, orders, and cancellation survey responses* and *Manage orders
     and subscriptions*; enable the Google Play Android Developer API in the Cloud
     project; store its JSON key as the `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` secret.
  4. Real-time developer notifications: Pub/Sub topic `play-subscription-rtdn` in
     `<prod>`, grant `google-play-developer-notifications@system.gserviceaccount.com`
     the *Pub/Sub Publisher* role on it, enter
     `projects/<prod>/topics/play-subscription-rtdn` in Play Console → Monetize →
     Monetization setup, choose subscriptions **and** one-time products, send a test
     message.
- **Expected:** products are *Active*; the test notification reaches the function.
- **Verify:** the function log shows the test notification being acknowledged; a license
  tester can buy Boost (step 14).

### Step 12 — Legal and policy
- **Where:** with counsel; then Play Console → App content.
- **Action:**
  1. Have the policy texts reviewed (`hosting/public/*.html` and the in-app copies in
     `lib/l10n/app_*.arb`). They are engineering drafts. Supply the **data controller's
     legal identity and address** and decide the **support address** — both are missing
     today, and every page now uses `destek@mevora.com` (2026-10-02) — make sure that mailbox exists and is read.
  2. Child safety: put a real procedure in place for reporting confirmed child sexual
     abuse material to the competent authority, and name the child-safety contact. The
     public page and the in-app guidelines already *promise* reporting; today no
     procedure exists. Only then self-certify — §4.5.
  3. Turkish data-protection obligations (KVKK registration, cross-border transfer basis
     for Google, Didit and Spotify) — counsel's call.
  4. Decide retention horizons for moderation records, set
     `ADMIN_RETENTION_ENFORCE=true`, and state the horizons in the policy.
- **Expected:** approved texts, a named contact, a written reporting procedure.
- **Verify:** the HTML comments marking the pages as drafts can be removed.

### Step 13 — Fill in Play Console → App content and the store listing
- **Where:** Play Console.
- **Action:** privacy policy URL, app access (reviewer account), ads (none), content
  rating questionnaire, target audience (18+ only, **Restrict minor access on**), Data
  safety, child safety standards, financial features (none), health (none), advertising
  ID (not used); then the listing text and graphics. Sources:
  `docs/PLAY_STORE_LISTING.md` and `docs/PLAY_DATA_SAFETY_INVENTORY.md`.
- **Expected:** every App content item shows a green tick.
- **Verify:** Play Console → Dashboard has no open "set up your app" task.

### Step 14 — Test the Play-distributed build on a real phone
- **Where:** a phone that installed the app **from the Internal testing track** (not a
  side-loaded build — Play Integrity and billing only work for store installs).
- **Action:** run the checklist in §7.
- **Expected:** every line passes.
- **Verify:** record the results; anything failing becomes its own fix branch.

### Step 15 — Final Production Acceptance, then `preview` → `main`
- **Where:** the separate *MEVORA — Final Production Acceptance* run.
- **Action:** run it against the candidate. Only if it passes: approve the
  `preview` → `main` PR and freeze the release candidate.
- **Expected:** `main` is the release candidate.
- **Verify:** `git rev-list --count origin/main..origin/preview` is 0.

### Step 16 — Closed testing and production access
- **Where:** Play Console → Testing → Closed testing.
- **Action:** personal accounts: at least 12 testers opted in for 14 days, then *Apply
  for production*. Organization accounts: closed testing is optional but recommended.
- **Expected:** production access granted.
- **Verify:** the Production track accepts a release.

### Step 17 — Production release
- **Where:** Play Console → Production.
- **Action:** follow §8. A **first** release cannot be staged — staged rollout exists
  only for updates — so limit the first release by **country** instead.
- **Expected:** the app is live for the chosen countries.
- **Verify:** install from the public listing; watch the gates in §8.

---

## 3. Where each kind of work stands

| Kind | State |
|---|---|
| **Repo complete** | Signing guards; entrypoint guard; flavor/environment guard; permission clean-up; mock/emulator gating; policy pages; in-app policy accuracy; readiness tool and CI step; Boost and Premium purchase integrity; paywall disclosures; Didit sandbox gate and erasure binding; export and deletion gaps; push token on sign-in; Apple button hidden on Android — §9 |
| **Owner action** | Steps 1, 2, 4, 8, 10 |
| **Play Console action** | Steps 3, 5, 11, 13, 16, 17 |
| **Firebase / GCP action** | Steps 2, 6, 7, 9, 11 |
| **Legal / policy action** | Step 12 |
| **Test action** | Steps 14, 15 |
| **Final submission action** | Steps 16, 17 |

---

## 4. Reference — what the audit established

### 4.1 Android release configuration

| Item | Value |
|---|---|
| Application ID / namespace | `com.mevora.app` |
| compileSdk / targetSdk | 37 / 37 (Google Play requires 36+ since 2026-08-31) |
| minSdk | Flutter default for 3.41.9 |
| Version | `1.0.1+2` from `pubspec.yaml` → versionName 1.0.1, versionCode 2. Raise the build number for every upload. |
| Flavors | `development` (same applicationId as production, debug-signed), `staging` (`.staging`), `production` |
| Billing library | `in_app_purchase_android` 0.5.0 = Play Billing Library 8 (required since 2026-08-31) |
| Shrinking | Flutter defaults; no project ProGuard file. A full production bundle was built during this preparation (§10) |
| Backups | `allowBackup="false"`, data extraction rules exclude everything |
| Cleartext | debug manifest only |
| Exported components | `MainActivity` only |
| Deep links | `mevora://auth/spotify`, `mevora://verify/identity`, and an `autoVerify` App Link for `https://mevora.app/auth/spotify` — the App Link cannot verify until `assetlinks.json` is served from `mevora.app`; the custom scheme works without it |
| 16 KB page size | Required for target API 35+; **not verified here** — check the Play Console pre-launch report / bundle explorer after the first upload |

### 4.2 Permissions

| Permission | Why | User flow | Play declaration |
|---|---|---|---|
| `INTERNET` | everything | — | none |
| `com.android.vending.BILLING` | Play Billing | Boost, Premium | none |
| `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION` | nearby discovery | location step in onboarding, foreground only | Data safety: precise + approximate location. No background-location form. In-app rationale is shown before the system prompt. |
| `CAMERA` | profile photo, verification selfie, chat photo | photo pickers, Face Anchor | none |
| `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS` | voice notes in chat; calls | chat | none |
| `BLUETOOTH` (≤ API 30), `BLUETOOTH_CONNECT` | headset routing for calls | calls (currently switched off) | none |
| `POST_NOTIFICATIONS` | push | asked in context | none |

Removed in this preparation:

- `READ_MEDIA_IMAGES`, `READ_MEDIA_VISUAL_USER_SELECTED` — every photo is chosen through
  the system photo picker, which needs no permission. Play's Photo and Video Permissions
  policy does not allow these for one-off picks.
- `com.google.android.gms.permission.AD_ID`, `ACCESS_ADSERVICES_AD_ID`,
  `ACCESS_ADSERVICES_ATTRIBUTION` — merged in by Firebase Analytics; Mevora shows no ads.

Plugins merge a few more into the release manifest, none of which needs a declaration:
`ACCESS_NETWORK_STATE`, `WAKE_LOCK`, `USE_BIOMETRIC` / `USE_FINGERPRINT` (secure storage),
`com.google.android.c2dm.permission.RECEIVE` (push) and the install-referrer binding. The
location plugin declares a location foreground *service*, but the app holds no
`FOREGROUND_SERVICE` permission and never starts it, so no foreground-service declaration
is due.

Open owner decisions: drop `ACCESS_FINE_LOCATION` if city-level accuracy is enough (the
code asks for medium accuracy only; removing it would also remove "precise location" from
Data safety), and drop the Bluetooth permissions while calls stay off.

### 4.3 Firebase, App Check, telemetry

- Environment is chosen by the Dart entrypoint; the build now fails, and the app refuses
  to start, when flavor and entrypoint disagree.
- Emulators, QA sign-in, test phone numbers and the emulator test store are reachable
  from the **development** environment only. `USE_MOCK_*` defines are ignored outside
  development debug builds.
- App Check: Play Integrity in production. All member-facing callables enforce it outside
  the Functions emulator; admin commands deliberately do not (BFF secret + MFA + roles).
- Crashlytics and Analytics collect outside development; no user identifier is set.
- Server-side fakes (purchase approval, face provider, dev clocks) are gated on
  `FUNCTIONS_EMULATOR === "true"`, which a deployed function never has.

### 4.4 Sign-in and providers

| Provider | Repository state | Needs from the owner |
|---|---|---|
| Phone (SMS) | implemented | Billing (step 2), SHA + Play Integrity (steps 6–7) |
| Google | implemented; production web client ID is in `AppConfig` | SHA registration (step 6) |
| Email + password | implemented | enable in console (step 7) — also the reviewer's sign-in |
| Spotify | PKCE in the app, token exchange on the server, tokens unreadable by clients | step 8 |
| Apple | iOS only; hidden on Android | nothing for Android |
| Didit identity | fails closed: a sandbox configuration cannot grant a badge on a deployed project unless explicitly allowed | live credentials (step 8) |
| Face Anchor | fails closed without a live key; selfie deleted after the check | step 8, then `FACE_ANCHOR_ENFORCEMENT=on` |

### 4.5 Dating / UGC / child safety

What exists: report (profile and chat) with reasons including *underage*; block; unmatch;
a staff console with report, case, photo, appeal and audit queues; warn / suspend / ban /
restore; member-side appeals; an 18+ gate enforced on the server with an immutable birth
date; photo verification.

What the owner must know before certifying anything:

- **Photos are not content-screened.** They are published after technical checks; a human
  looks only after a report. One report hides the reported profile until reviewed.
- **Messages cannot be read by staff** (end-to-end encryption). A chat report carries
  references and the reporter's description, not the content.
- **No reporting procedure to authorities exists yet** (step 12).
- **Review capacity is whoever holds a staff account.** Do not state response times you
  cannot keep.
- Banned members cannot sign in, so their appeal and deletion route is email.

Play requirements for a dating app, and where each is met:

| Requirement | Met by |
|---|---|
| Published standards against CSAE | `<site>/child-safety` |
| In-app way to report | Report on profile and chat |
| Action on CSAM | Staff tooling to remove content and close accounts — the reporting procedure is step 12 |
| Compliance with child-safety law | step 12 |
| Named point of contact | step 12, entered in Play Console |
| Restrict minor access | step 13 |
| Terms accepted before posting UGC | "By continuing you agree…" on sign-in. Acceptance is not recorded with a version — a known gap |

### 4.6 Account deletion and export

- In-app: Settings → Account → Delete account. Immediate, no grace period.
- Web: `<site>/delete-account`. Members who cannot sign in (banned, or stuck in
  onboarding) write to the support address; **handling those emails is a manual owner
  process** — verify ownership, then delete from the console.
- Export: Settings → Account → Download my data. It contains no message content and, after
  this preparation, no coordinates.

---

## 5. Play Billing — identifiers the code expects

| Thing | Value | Where it comes from |
|---|---|---|
| Package | `com.mevora.app` | `ANDROID_PACKAGE_NAME` default; `PREMIUM_ANDROID_PACKAGE_NAME` must be set |
| Boost products (one-time, consumable) | `mevora_boost_7_days`, `mevora_boost_1_month`, `mevora_boost_1_year` | `lib/features/boost/domain/config/boost_pack_catalog.dart` |
| Premium subscription | **not defined in code** — the owner chooses. The emulator and tests model `mevora_premium` with base plans `monthly` and `yearly` | `PREMIUM_ANDROID_PRODUCT_IDS=productId:basePlanId,…` in the functions environment **and** as a `--dart-define`, identical in both |
| Service account key | secret `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | bound on `verifyBoostPurchase`, `verifyPremiumPurchase`, `onPlaySubscriptionNotification`, `reconcileVoidedBoostPurchases` |
| RTDN topic | `play-subscription-rtdn` (override: `PREMIUM_RTDN_TOPIC`) | `functions/src/subscription/googleRtdnFunction.ts` |

How a purchase is granted: the app sends the purchase token to the server; the server
asks Google; only the server writes the entitlement or the boost; Firestore rules refuse
every client write to those documents. A Boost token is recorded by its own hash, so it
grants once, for one account. The app completes a purchase only after the server confirms.

A refunded Boost is taken back. When Google voids a Boost purchase — a refund, a
chargeback, a revoked order — the ledger entry is marked `voided` and what the member has
not used yet is removed: the days of the Boost that still lie ahead, or the wallet credits
that are still there. Time already used, and time another purchase paid for, stays; a
wallet never goes below zero. The entry records what was taken back (`void`), and the
token can never be granted again. Two paths lead there and both are idempotent:

- the `voidedPurchaseNotification` on the RTDN topic, handled by
  `onPlaySubscriptionNotification` — it works without Premium being configured;
- `reconcileVoidedBoostPurchases`, once a day, which asks the Voided Purchases API for the
  last 29 days. It is the fallback when notifications are not configured or one was
  missed, and it needs the service account's *View financial data* permission (step 11).

An interrupted Boost purchase — paid, app closed before the server confirmed — is
submitted again by itself at the next app start or sign-in on Android. *Restore purchases*
still does the same on demand.

Not built, and worth knowing:

- A purchase left unfinished on a phone is granted to whichever Mevora account next signs
  in on that phone: Play knows the Google account, not the Mevora one. *Restore
  purchases* has always behaved this way.
- The member is not notified when a refunded Boost ends.
- Promotional subscription offers are never selected; the base price is bought.
- A license tester's purchase grants a real entitlement (recorded as sandbox).

---

## 6. Humor Core release

Humor is off in release builds by default, and the sequence is a draft:
`HUMOR_CORE_RELEASE.released = false`, 36 clips, 33 of them tagged English and 3 Turkish,
all third-party GIFs loaded from GIPHY. Thirty-six clips last a new member the first
fifteen plus about four days.

While `released` is `false` a deployed backend serves no Core content: the feed answers
an empty catalogue, the daily set stays locked and a rating is refused (`not-in-set`).
Only the emulator hands out the draft. The build flag is the second barrier: with humor
switched on before the release, members would see an empty Humor Lab, not the draft. Once
members have rated a sequence it can only grow at the end, so do not release it before it
is final.

Owner procedure:

1. Review the current sequence: admin console `/Humor/Core`, or locally
   `node tool/seedEmulatorHumorCatalog.cjs` against the emulator, which prints V1…V36
   with category, humor vector and source.
2. Find candidates: `node tool/humorCuratorSearch.cjs --out .tmp/humor-curation/candidates.json --stills .tmp/humor-curation/stills`
   (emulator and a GIPHY key only) and open the generated `review.html`.
3. Give the final list and order. It is applied in a branch:
   `functions/src/humor/calibrationSeed.ts` and `functions/src/humor/coreSequence.ts`,
   then `node tool/lockHumorCoreSequence.cjs --redraft`, then `released: true` **and** the
   assertion in `functions/test/humorCoreSequence.test.cjs` that currently expects
   `false`, then `npm --prefix functions test`.
4. From then on: `node tool/lockHumorCoreSequence.cjs` only (append).
5. After deploy, seed production with `seedInternalHumorContent`.

Details: `docs/HUMOR_LAB.md` → "Humor Core sequence".

---

## 7. Device test checklist (step 14)

Run on a phone that installed the build from Play. Record pass / fail for each line.

**Start-up and sign-in**
- [ ] The app starts (no startup error screen) and shows the sign-in screen.
- [ ] Phone sign-in: a real SMS arrives, the code signs in.
- [ ] Google sign-in works.
- [ ] Email sign-in works (the reviewer's route).
- [ ] No "Continue with Apple" button on Android.

**App Check**
- [ ] After sign-in, Picks loads — proves callables accept the Play Integrity token.

**Onboarding and photos**
- [ ] Under-18 birth date is refused.
- [ ] Adding a photo from the gallery opens the system photo picker and asks for **no**
      permission.
- [ ] Camera photo asks for the camera permission in context.
- [ ] Photo verification completes with a real selfie (live Didit).

**Notifications** (two phones, two accounts)
- [ ] Sign in on a fresh install, allow notifications: `users/{uid}/devices` gets a token
      without restarting the app.
- [ ] A new match produces one push on the other phone; tapping it opens the match.
- [ ] A new message produces one push with no message text in it; tapping opens the chat.
- [ ] With message notifications switched off in settings, no push arrives.
- [ ] Sign out: the next message produces no push on that phone.
- [ ] Sign in as a different account on the same phone: pushes for the first account do
      not arrive.
- [ ] Delete the account: no push arrives afterwards.

**Purchases** (license tester)
- [ ] Boost: the three packs show store prices; buying one activates it once.
- [ ] Buying, then killing the app before confirmation, then opening the app again grants
      it exactly once, without tapping *Restore purchases*.
- [ ] Refund a test Boost order in Play Console: within minutes the Boost ends in the app
      and `purchases/android_…` reads `status: voided` (or within a day, through the
      sweep, if notifications are not configured).
- [ ] Premium (if shipped): each plan shows price and period; buying the yearly plan buys
      the yearly plan; *Manage subscription* opens Google Play.
- [ ] Cancel in Google Play: access remains until the period ends, then stops.
- [ ] The RTDN test message from Play Console is acknowledged in the function log.

**Safety and account**
- [ ] Report from a profile and from a chat reaches the staff console.
- [ ] Block removes the person and ends the conversation.
- [ ] Privacy, Terms and Guidelines open from Settings → Support.
- [ ] Download my data produces a file without coordinates.
- [ ] Delete account signs out and the account cannot sign in again.

**Spotify**
- [ ] Connect Spotify returns to the app and shows music taste.

---

## 8. Rollout plan (prepared, not executed)

1. **Internal testing** — the owner and a few phones. Run §7.
2. **Closed testing** — required for a personal account (12 testers, 14 days); use it for
   the two-device acceptance in any case.
3. **Apply for production** (personal accounts).
4. **Production, first release.** Staged rollout is not available for a first release:
   - release to **Türkiye only**; add countries later, one batch at a time;
   - keep `FACE_ANCHOR_DAILY_GLOBAL_CAP` and any spending alerts conservative;
   - submit early in the week so problems surface on working days.
5. **Updates** — use staged rollout: 5 % → 20 % → 50 % → 100 %, at least a day per stage.

**Watch, and stop when a gate is crossed.** Halting: Play Console → Production → Manage
rollout → Halt (members who already updated keep that version; a fully rolled-out release
can also be halted, and the previous one is served again).

| Signal | Where | Halt or act when |
|---|---|---|
| User-perceived crash rate | Play Console → Android vitals; Crashlytics | above **1.09 %** (Play's bad-behaviour threshold), or any new crash in start-up, sign-in or purchase |
| ANR rate | Android vitals | above **0.47 %** |
| Sign-in failures | Crashlytics logs, Firebase Auth | SMS not arriving, Google sign-in errors after an update — usually a fingerprint or App Check problem |
| Cloud Functions errors | Google Cloud → Functions → Logs / Error Reporting | error rate above normal on `completeOnboarding`, `getMevoraPicks`, `recordDiscoveryDecision`, `sendMessageNotification` |
| App Check rejections | Firebase → App Check → metrics | unverified requests from the released version |
| Purchase verification | logs of `verifyBoostPurchase`, `verifyPremiumPurchase` | any `unavailable`, or a purchase paid but not granted |
| RTDN | logs of `onPlaySubscriptionNotification` | messages retried repeatedly, or none arriving |
| Push delivery | `failedNotifications`, FCM reports | pushes not arriving after a release |
| Reports and moderation queue | admin console | queue growing faster than it is reviewed; **any child-safety report is same-day** |
| Account deletion | `deleteUserAccount` logs, deletion verification job, `identityErasurePending` | failed deletions or erasure requests piling up |
| Cost | Cloud Billing reports, budget alerts | Firestore reads, Functions invocations or Didit verifications far above forecast (`docs/PICKS_COST_MODEL.md`) |

Rollback of the backend is a redeploy of the previous `main`; rules and indexes roll back
the same way. A client release cannot be recalled — only halted and superseded.

---

## 9. What this preparation changed

Branches opened from `main` `7565ebda`, each with a pull request into `preview`:

| Branch | What |
|---|---|
| `chore/google-play-production-launch-readiness` | Gallery and advertising-ID permissions removed; release key limited to the production flavor; production release requires `lib/main_production.dart`; flavor/environment start-up guard; `USE_MOCK_*` gating; policy pages (TR + EN) with `/delete-account` and `/child-safety`; in-app policy accuracy (including the Turkish privacy policy that said the app was for under-18s); `tool/productionReadiness.cjs` and its CI step; this document, the Data safety inventory and the store listing package |
| `fix/boost-purchase-integrity` | A Boost purchase token could be replayed under another transaction id or another account; the app consumed a purchase even when verification failed |
| `fix/premium-purchase-integrity` | Purchases acknowledged without an entitlement when the backend was misconfigured; the tapped plan ignored for multi-plan subscriptions; pending purchases hanging; an old token able to expire a live entitlement; RTDN not retried; the Play service account read from a plain environment variable instead of a secret |
| `feat/paywall-subscription-disclosures` | Billing period, renewal terms, cancel path, Terms / Privacy links and *Manage subscription* on the paywall; one-time-purchase note on Boost |
| `fix/didit-production-readiness` | A sandbox Didit configuration could grant the verified badge on a deployed project; provider-side erasure could never run because the functions lacked the secret |
| `fix/account-export-location-and-deletion-gaps` | The data export contained exact coordinates; account deletion left `boostReach` and two rate-limit counters behind |
| `fix/fcm-token-on-sign-in` | No push notifications after signing in until the next cold start |
| `fix/hide-apple-sign-in-on-android` | A sign-in button that always failed on Android |
| `fix/smoke-user-random-password` | Smoke-test accounts had a password anyone could derive from the repository; the shared secret was compared in non-constant time |
| `feat/report-reason-child-safety` | A dedicated *Child safety* report reason, reviewed at the highest priority, in the app and the staff console |
| `fix/boost-refund-and-purchase-recovery` (from `preview`, on top of the two purchase-integrity branches) | A refunded or charged-back Boost was kept; an interrupted Boost purchase waited for the member to tap *Restore purchases* |

Each pull request carries its own deploy note. All of them need a functions redeploy that
is owner-run and waits on billing.

### Found, not fixed — follow-up branches

| Finding | Why it was left |
|---|---|
| `profiles/{uid}` is readable by any signed-in member, including the exact birth date | Needs a data-model change (private document or server projection) |
| Reports against a deleted account are deleted; nothing recognises a banned person re-registering | Policy decision first (owner / counsel) |
| Profile photos are not content-screened before publication | Needs a moderation provider or a pre-publication review decision |
| Members stuck in onboarding and banned members have no in-app deletion path | Web route exists; in-app change touches onboarding |
| No Android notification channel; foreground non-call pushes are dropped | Product decision on channels |
| Terms acceptance is not recorded or versioned | Needs a small data-model addition |
| Remote Config is a stub, so features can only be switched at build time | Feature work |
| Twelve functions deployed on `mevora-d6ed0` exist on no branch | `docs/DEPLOY_NOTES.md`; irrelevant for Option A |
| Four emulator-only callables (`prepareSmokeTestUsers`, `cleanupSmokeTestUsers`, `searchHumorProviderCandidates`, `debugPersonalizationRanking`) may still be live on `mevora-d6ed0` from earlier deploys | No longer in the deploy surface, and `SMOKE_TEST_SECRET` is no longer needed. Deleting the live copies is an owner decision: `docs/DEPLOY_NOTES.md` → "Emulator-only callables" |
| No staff sanction code specific to child sexual abuse material | Add with the reporting procedure (step 12) |
| Promotional subscription offers, and a dedicated "purchase pending" message on the paywall | Small follow-ups to the Premium work |
| Legacy launcher PNGs and the iOS icon still show a placeholder "M" | Needs the final artwork |

---

## 10. Verification record

Release build, run on 2026-10-01 from the launch-readiness branch. The signed checks used
a throwaway keystore that was generated for the check and deleted afterwards; no release
artifact was kept.

| Check | Command | Result |
|---|---|---|
| No signing material | `flutter build appbundle --flavor production -t lib/main_production.dart --release` | **Stops in 39 s**: "Production release signing is not configured. Refusing to sign a production release with the debug keystore." |
| Signing present, default entrypoint | `flutter build appbundle --flavor production --release` | **Stops in 10 s**: "A production release must be built from lib/main_production.dart, not lib/main.dart." |
| Signing present, production entrypoint | `flutter build appbundle --flavor production -t lib/main_production.dart --release` | **Builds** a 74 MB bundle signed by the configured key. Merged manifest: `com.mevora.app`, versionCode 2, versionName 1.0.1, minSdk 24, targetSdk 37, not debuggable, no media / storage / advertising-ID permission |
| Development release with signing present | `flutter build apk --flavor development -t lib/main_development.dart --release` | **Debug-signed** (`CN=Android Debug`), label "Mevora Dev" — never the release key |

One observation from those builds: the SHA-256 registered today on both Firebase projects
is the **debug keystore's**. Nothing a store build is signed with is registered yet
(step 6).

Not verified here, by design: anything that needs the owner's upload key, a
Play-distributed install, a real purchase, a live Didit key or a production deploy —
that is step 14. Automated test counts for the integrated `preview` are in the launch
session's final report and on the session board.

---

## 11. Index of reference documents

| Document | Use |
|---|---|
| `docs/PUBLISH_BLOCKERS.md` | The short list of open blockers |
| `docs/ANDROID_RELEASE_SIGNING.md` | Upload key, Play App Signing, fingerprints, build command |
| `docs/PLAY_DATA_SAFETY_INVENTORY.md` | Data safety form answers, with code references |
| `docs/PLAY_STORE_LISTING.md` | Listing text, URLs, questionnaires, reviewer access, assets |
| `docs/DEPLOY_NOTES.md` | How to deploy functions without deleting live ones |
| `docs/HUMOR_LAB.md` | Humor Core sequence and release |
| `docs/FACE_ANCHOR.md`, `docs/DIDIT_INTEGRATION.md`, `docs/IDENTITY_VERIFICATION_PRIVACY.md` | Verification |
| `docs/PHOTO_MODERATION.md`, `docs/ADMIN_TRUST_SAFETY_ARCHITECTURE.md` | Moderation and the staff console |
| `docs/E2EE_SECURITY.md` | Message encryption |
| `docs/DATA_RETENTION_PLAN.md` | Deletion and retention design |
| `PAYMENT_ARCHITECTURE.md` | Boost and Premium |

Superseded — kept for history, do not act on them: `docs/QA_PRODUCTION_READINESS.md`,
`docs/QA_BUG_REPORT.md`, `docs/QA_TEST_RESULTS.md`, `docs/QA_RECOMMENDATIONS.md`,
`docs/QA_MASTER_TEST_PLAN.md`, `docs/MEVORA_NIGHTLY_QA_REPORT.md`,
`docs/MEVORA_CURRENT_STATE_AND_STORE_ROADMAP.md`, `docs/SUPPORT_LEGAL_QA_REPORT.md`,
`docs/PRIVACY_STORE_READINESS.md`, `docs/SUMSUB_SETUP.md`.
