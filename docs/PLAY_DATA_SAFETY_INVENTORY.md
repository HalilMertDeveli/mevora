# Google Play Data Safety — technical inventory

**What this is:** a map from what the Mevora app and backend actually do (code as of
2026-10-01) to the questions in Play Console → *App content → Data safety*.
**What this is not:** legal advice, or a submission. The owner fills in the form and is
responsible for the answers; where a judgement call exists it is marked **DECISION**.

Rule used throughout: this inventory does not shrink the list to make the form look
better. Where a category is arguable, the conservative answer is the recommended one.

Parent document: `docs/GOOGLE_PLAY_PRODUCTION_LAUNCH.md`.

## How Google defines the terms

- **Collected** — the app sends the data off the device, to you or to anyone else,
  including through SDKs. Data that never leaves the device, and data that is
  end-to-end encrypted so that you cannot read it, does not count.
- **Shared** — transferred to a third party. *Not* sharing: a service provider processing
  the data on your behalf, a transfer the user asked for, a legal requirement.
- Internal testing is exempt; the form is required from closed testing onwards.

Every provider Mevora uses acts as a service provider (Google/Firebase, Didit) or
receives data because the member chose to connect it (Spotify). On that basis the
recommended answer to "Is any of this data shared with third parties?" is **No** for
every type below. **DECISION:** confirm with counsel that the Didit and Google terms the
owner accepted make them processors acting on Mevora's instructions.

## Form: overview questions

| Question | Answer | Basis |
|---|---|---|
| Does your app collect or share any of the required user data types? | **Yes** | see table |
| Is all of the user data collected by your app encrypted in transit? | **Yes** | All traffic is HTTPS/TLS to Firebase, Spotify, Didit and GIPHY. Cleartext is allowed only in the debug manifest (`android/app/src/debug/AndroidManifest.xml`), never in a release. |
| Do you provide a way for users to request that their data is deleted? | **Yes** | In-app: Settings → Account → Delete account (`deleteUserAccount`, `functions/src/deleteAccount.ts`). Web: `/delete-account` (`hosting/public/delete-account.html`). |
| Delete account URL | `https://<production site>/delete-account` | The host depends on the production-project decision in the launch document. |
| Has the app been independently security reviewed? | **No** | No such review exists. Do not tick it. |
| Committed to the Play Families policy? | **No / not applicable** | 18+ only. |

## Data types

Columns: **C** collected · **S** shared · **Req** required or optional for the member ·
purposes use Google's labels (AF app functionality, AN analytics, FP fraud prevention /
security / compliance, PE personalization, AM account management).

### Location

| Type | C | S | Req | Purposes | What it is in Mevora | Where |
|---|---|---|---|---|---|---|
| Approximate location | Yes | No | Required | AF, PE | City and distance band shown to other members | `profiles/{uid}.city`, discovery projections |
| Precise location | **Yes** | No | Required | AF, PE | Latitude/longitude and a geohash are stored server-side to compute distance. The manifest declares `ACCESS_FINE_LOCATION`; the code asks for medium accuracy. Never shown to other members. Foreground only. | `userLocation/{uid}`, `users/{uid}.location` · `lib/features/location/data/datasources/firebase_location_data_source.dart` |

**DECISION:** if the owner later drops `ACCESS_FINE_LOCATION` and stores a rounded
position only, "Precise location" can be removed. Today it must be declared.

### Personal info

| Type | C | S | Req | Purposes | What it is | Where |
|---|---|---|---|---|---|---|
| Name | Yes | No | Required | AF, AM | First name (public), surname (private) | `profiles/{uid}.displayName`, `users/{uid}.lastName` |
| Email address | Yes | No | Optional (depends on sign-in method) | AM, AF | Email sign-in, Google, Spotify | Firebase Auth, `users/{uid}` |
| User IDs | Yes | No | Required | AM, AF, FP | Firebase UID, Google / Apple / Spotify account IDs | Firebase Auth, `users/{uid}` |
| Phone number | Yes | No | Optional (depends on sign-in method) | AM, FP | Phone sign-in | Firebase Auth |
| Sexual orientation | **Yes** | No | Required | AF, PE | Gender and "who you want to meet" together reveal orientation | `profiles/{uid}` |
| Other info | Yes | No | Required | AF, PE | Date of birth, gender, bio, relationship goal, education, height, smoking and drinking habits | `profiles/{uid}` |
| Address, race and ethnicity, political or religious beliefs | No | — | — | — | Not asked anywhere | — |

Identity verification (optional): the member's ID document and selfie are processed by
Didit in Didit's hosted flow; Mevora stores only the outcome
(`users/{uid}/verification/identity`). **DECISION:** declare the document under
"Personal info → Other info" with purpose FP. Recommended, because the flow is started
from inside the app.

### Financial info

| Type | C | S | Req | Purposes | What it is | Where |
|---|---|---|---|---|---|---|
| Purchase history | Yes | No | Optional | AF | Product, purchase-token hash and status of Boost and Premium purchases | `purchases/*`, `subscriptionPurchases/*`, `users/{uid}/subscription/current`, `users/{uid}/boosts/*` |
| User payment info, credit score, other | No | — | — | — | Google Play takes the payment; Mevora never sees card data | — |

### Health and fitness

Not collected. **DECISION:** smoking and drinking habits are lifestyle answers shown on
the profile, declared above under "Personal info → Other info". If counsel regards them
as health information, declare "Health info" as well.

### Messages

| Type | C | S | Req | Purposes | What it is | Where |
|---|---|---|---|---|---|---|
| Other in-app messages | **Yes (recommended)** | No | Optional | AF | Chat content is end-to-end encrypted (Firestore rules refuse a plaintext message) and unreadable to Mevora, which by Google's definition is not "collected". Delivery metadata — sender, recipient, time, type, read state — is stored, and support-ticket text is stored in plaintext. | `matches/{id}/messages/*`, `supportTickets/*` · `docs/E2EE_SECURITY.md` |
| Emails, SMS or MMS | No | — | — | — | The app does not read either | — |

**DECISION:** declaring "collected" is the conservative answer and is recommended
because of the metadata and the support tickets.

### Photos and videos

| Type | C | S | Req | Purposes | What it is | Where |
|---|---|---|---|---|---|---|
| Photos | Yes | No | Required | AF, FP | Profile photos (3–6), the verification selfie (sent to Didit, deleted when the check ends), chat images (encrypted), support attachments | Storage `users/{uid}/profile/*`, `face-anchor/pending/*` (temporary), `users/{uid}/chat/*`, `users/{uid}/support/*` |
| Videos | No | — | — | — | No video upload. Video calls are switched off (`videoCallsEnabled` defaults to false). **If calls are enabled later, revisit this and add LiveKit to the provider list.** | — |

No gallery permission is requested: photos are chosen through the system photo picker.

### Audio

| Type | C | S | Req | Purposes | What it is | Where |
|---|---|---|---|---|---|---|
| Voice or sound recordings | **Yes (recommended)** | No | Optional | AF | Voice notes in chat. They are encrypted on the device like message text; declared for the same conservative reason. | Storage `users/{uid}/chat/*` |
| Music files, other audio | No | — | — | — | Mevora reads no local audio | — |

### App activity

| Type | C | S | Req | Purposes | What it is | Where |
|---|---|---|---|---|---|---|
| App interactions | Yes | No | Required | AF, AN, PE | Likes, passes, matches, humor ratings, daily streak, Picks decisions, analytics events (coarse, no user ID) | `likes/*`, `users/{uid}/passedUsers`, `users/{uid}/humor*`, Google Analytics for Firebase |
| Other user-generated content | Yes | No | Required | AF, PE | Bio, relationship and daily question answers, reports filed, support tickets, appeals | `profiles/{uid}`, `users/{uid}/relationshipAnswers`, `reports/*`, `supportTickets/*` |
| Other actions | Yes | No | Optional | AF, PE | Spotify listening taste when the member connects Spotify: top artists and tracks, recently played, playlists, followed artists | `users/{uid}/music/*`, `profiles/{uid}.publicMusic` · `functions/src/spotifyMusic.ts` |
| In-app search history, installed apps | No | — | — | — | Neither exists | — |

### App info and performance

| Type | C | S | Req | Purposes | What it is | Where |
|---|---|---|---|---|---|---|
| Crash logs | Yes | No | Required | AN | Firebase Crashlytics, enabled outside development. No user identifier is set. | `lib/core/services/firebase/firebase_bootstrap.dart` |
| Diagnostics | Yes | No | Required | AN | Google Analytics for Firebase app events | `lib/core/analytics/firebase_analytics_adapter.dart` |

### Device or other IDs

| Type | C | S | Req | Purposes | What it is | Where |
|---|---|---|---|---|---|---|
| Device or other IDs | Yes | No | Required | AF, FP, AN | FCM registration token, Firebase installation ID, App Check / Play Integrity attestation | `users/{uid}/devices/*`, Firebase SDKs |

The **advertising ID is not used**: the `AD_ID` permission is removed from the manifest.
Answer "No" to *Does your app use an advertising ID?* in Play Console.

### Not collected at all

Contacts, calendar, files and docs, web browsing history, SMS, call logs, installed apps.
The manifest declares none of the corresponding permissions.

## Providers

| Provider | Role | Data it receives | Why |
|---|---|---|---|
| Google — Firebase Auth, Firestore, Storage, Functions, FCM, App Check, Crashlytics, Analytics | Service provider | Everything in the tables above | Core backend, notifications, abuse prevention, diagnostics |
| Google Play (Billing, Developer API) | Store | Purchase token and product ID | Purchases and their server-side verification |
| Didit | Service provider | Selfie and the chosen profile photo (photo verification); ID document, selfie and liveness in the optional identity flow; the member's uid as a reference | Verification |
| Spotify | Connected by the member | OAuth code; Mevora reads the member's profile and listening data | Sign-in and music compatibility |
| GIPHY | Content source | The device fetches humor media directly from GIPHY, so GIPHY sees the device's IP address and user agent. No account data is sent. | Humor content |
| LiveKit | **Not active** | Would receive the uid and call media | Calls are switched off |

Not used, despite older documents: Sumsub (replaced by Didit; only an inert stub remains),
Rive, any advertising SDK, any maps or geocoding service.

## Deletion and retention, for the form's free-text fields

Deleted on account deletion: account and sign-in details, profile and photos, location,
messages and chat media, likes and passes, answers and humor ratings, Spotify tokens and
music data, device tokens, verification status (plus an erasure request to Didit),
purchase records, support tickets, appeals, reports made by or about the member.

Kept: closed match records (ids only, no name or photo), other members' own block and
pass entries, moderation actions and the staff audit log, pseudonymous boost-reach and
personalization counters held under other members' accounts.

Retention horizons for the kept safety records exist in code
(`functions/src/admin/retention.ts`: 1095 / 730 / 730 days) but the sweep runs in
**dry-run** until the owner sets `ADMIN_RETENTION_ENFORCE=true`. Until then those records
are kept indefinitely — the public policy therefore promises no specific period.
**OWNER ACTION:** decide the horizons, enable enforcement, then state them in the policy.

## Known gaps between this inventory and the product

These are engineering findings, not form answers. They are tracked in the launch document.

- `profiles/{uid}` is readable by any signed-in member under the Firestore rules,
  including the exact date of birth. The app shows only the age.
- Deleting an account also deletes the reports filed against it, and nothing remains that
  could recognise a banned person who registers again.
- Profile photos are published after technical checks only; there is no automated
  content screening. Human review happens after a report.
