# Two-Device Core Dating Acceptance — setup

Tooling for running the A↔B acceptance (discovery → like → mutual match → chat) against the
Firebase Emulator Suite with the real Flutter app on two Android emulators.

This file exists because the equivalent setup has been rebuilt from scratch more than once.

## Why a separate emulator config

`FirebaseEmulatorConfig` hardcodes the ports — auth `9099`, firestore `8080`, functions `5001`,
storage `9199`. Only the **host** is configurable (`--dart-define=FIREBASE_EMULATOR_HOST`). So a
run needs those exact ports, and two runs cannot share a machine.

`firebase.qa.json` is `firebase.json` with the emulators bound to `0.0.0.0` so the Android
emulator can reach them over the host LAN IP:

```bash
firebase emulators:start --config firebase.qa.json --only auth,firestore,functions,storage --project mevora-d6ed0
```

Build `functions/` first (`npm --prefix functions ci && npm --prefix functions run build`).
Without `functions/lib` the Functions emulator fails to load and every Discover result is
meaningless rather than obviously broken.

## Host address

`10.0.2.2` is unreachable from the app sandbox on API 37 — the adb *shell* user reaches it fine,
so `nc` tests pass and mislead. Pass the host LAN IP instead:

```bash
--dart-define=USE_EMULATORS=true \
--dart-define=USE_AUTH_EMULATOR=true \
--dart-define=FIREBASE_EMULATOR_HOST=<host LAN IP>
```

Both emulator defines are needed: `USE_EMULATORS` alone leaves Auth pointed at live
`mevora-d6ed0`.

## Seeding the pair

```bash
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
QA_PASSWORD=<disposable> \
node tool/seedCoreQaUsers.cjs
```

Both scripts refuse to run unless the emulator hosts are set, so they cannot reach a cloud
project. `seedCoreQaUsers.cjs` seeds only the prerequisites the real discovery engine checks —
account, profile, preferences, location and photos. It deliberately creates **no** likes, matches,
conversations or messages; those must come from the real app during the run.

Two details the engine enforces that are easy to get wrong:

- **Three approved photos are required** (`MIN_PROFILE_PHOTOS = 3`), and approval is
  server-owned. Writing `moderationStatus: "approved"` onto `profiles/{uid}.photos` is reverted by
  `enforceProfilePhotoModeration`; the authority is the ledger at
  `users/{uid}/photoModeration/{imageId}`, which the seed writes first.
- **`isSmokeTestUser: true`** on both accounts uses the product's own
  `passesSmokeDiscoveryIsolation` gate, so the pair discovers only each other. Every other filter
  — gender preference in both directions, age, activity, completeness, discoverability — still has
  to pass genuinely. It makes the deck deterministic without weakening a single production rule.

## Reading backend state

```bash
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node tool/inspectCoreQa.cjs <uidA> <uidB>
```

Read-only. Reports match count (duplicate detection), the messages subcollection with
plaintext-vs-ciphertext per message, likes, and an identity sanity block per user.

Note that the conversation *is* the match: messages live at `matches/{matchId}/messages`, and
`firestore.rules` requires `encrypted == true` with a non-empty `ciphertext` and an empty `text`,
so a plaintext body in that output is a finding, not a formatting quirk.

## Diagnosing an empty deck

`getDiscoveryCandidates` accepts `includeDebug: true` and returns `rejectionReasons`, which names
the exact filter that dropped a candidate (`not_discoverable`, `profile_incomplete`,
`photos_insufficient`, `gender_preference`, `age_filter`, `inactive`, `already_seen_or_matched`,
`smoke_isolation`, …). Use it before assuming a product bug.

Also confirm the device actually reached the backend: `HybridDiscoveryRepository` falls back to
demo data in development, so a broken backend renders plausible `mock-*` profiles and a whole run
can look green while measuring nothing.

## Known emulator trap: GPS injection dies

On a long-lived emulator instance `adb emu geo fix` returns `OK` while silently updating nothing.
Symptom: onboarding reports "The location request timed out" even though `dumpsys location` shows
a fix.

Check the fix age before blaming the app — compare the location's `et=` against `/proc/uptime`:

```bash
adb -s <serial> shell dumpsys location | grep "last location"
adb -s <serial> shell cat /proc/uptime
```

A fix at `et=+5m56s` on a device with 15286s of uptime is four hours old. `getCurrentPosition`
then times out legitimately (no fresh fix is being produced) and the last-known fallback correctly
*refuses* it, because `GeolocatorLocationDevice` rejects a cached fix older than 10 minutes rather
than seeding discovery with a stale position. That is correct behaviour, not the `distanceFilter`
bug fixed earlier.

A device reboot does not always restore injection. When it does not, skip the location step and
pick a city — onboarding supports that path — and seed `userLocation/{uid}` instead.
