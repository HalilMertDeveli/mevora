# Mevora — Privacy / Store Technical Readiness Checklist

**Status:** Technical preparation. Not a claim of KVKK, GDPR, Google Play, or Apple compliance.

## Technical measures completed (this program)

- Firestore default-deny; reports CF-only; E2EE-required message creates; typing-only match meta.
- Storage: pending photos owner-read; legacy profile write closed; chat uploads encrypted blobs only.
- Incoming likes premium-gated server-side; GPS owner-only; FCM without message body.
- Account deletion expanded; App Check on callables (non-emulator); debug App Check token removed from source.
- Android `allowBackup=false` + extraction rules.
- Data export callable + in-app “Download my data”.
- E2EE fail-closed for new text/media; protocol honesty docs.

## Legal review required

- Privacy Policy / Terms wording for dating data categories, E2EE limits, moderation, retention.
- Lawful basis / consent for location, photos, messaging, analytics, Crashlytics.
- Cross-border transfers (Firebase/Google regions).
- Child safety / age gating processes beyond technical 18+ checks.
- Turkey KVKK VERBIS / DPO obligations if applicable.
- EU GDPR Art. 15–22 fulfillment procedures (export/deletion SLAs).
- Report evidence when E2EE prevents server content review.

## Google Play Data Safety (likely categories to declare)

- Personal info: name, email, phone, user IDs
- Photos / videos; audio (voice notes)
- Location (approximate / precise as collected)
- Messages (encrypted in transit/at rest from app perspective — disclose E2EE carefully)
- App activity / diagnostics (Crashlytics, Analytics)
- Device IDs / App Check / FCM tokens
- Third parties: Google Firebase, Sumsub, Spotify, LiveKit, Play Billing

## Apple App Privacy Nutrition Label (likely)

- Contact Info, Location, User Content (photos/messages), Identifiers, Diagnostics, Purchases
- Linked to user / used for tracking: review Analytics + any advertising SDK (none assumed)

## Store submission prep

- [ ] Privacy Policy URL live and linked in stores + in-app
- [ ] Data Safety / Privacy Nutrition forms filled by counsel + eng
- [ ] Account deletion path discoverable in-app (done) and documented for reviewers
- [ ] Production App Check (Play Integrity / App Attest) verified
- [ ] Release signing (not debug) + R8 plan
- [ ] Deploy updated Firestore/Storage rules + Functions before client fail-closed chat ships

## Third-party SDK disclosure

Firebase Auth/Firestore/Storage/Functions/Messaging/Crashlytics/Analytics/App Check, Google Sign-In, Apple Sign-In, Sumsub, Spotify, LiveKit, in_app_purchase, Geolocator, Rive.
