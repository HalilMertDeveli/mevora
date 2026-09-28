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

> Corrected 2026-09-28. This section used to say `10.0.2.2` is unreachable from the app
> sandbox on API 37. The address was never the problem — the *permission* was. Android 16
> put local-network access behind `ACCESS_LOCAL_NETWORK`, and without it the sandbox cannot
> reach the suite on any address while the adb *shell* user still can, so `nc` tests pass and
> mislead. The permission now ships in `android/app/src/debug/AndroidManifest.xml`, and
> `10.0.2.2` works again on an Android emulator.

On an Android **emulator** the default is correct and you need no host define: `10.0.2.2` is
the emulator's alias for the host loopback (`app_config.dart`). On a **real phone** that
address means nothing, so pass the host LAN IP:

```bash
--dart-define=USE_EMULATORS=true \
--dart-define=USE_AUTH_EMULATOR=true \
--dart-define=FIREBASE_EMULATOR_HOST=<host LAN IP>
```

Both emulator defines are needed: `USE_EMULATORS` alone leaves Auth pointed at live
`mevora-d6ed0`.

## Real phones

Two handsets on the same Wi-Fi as the host, both talking to the one Emulator Suite.

**1. Open the firewall, once.** This is the step that silently sinks the whole setup:
`firebase.qa.json` already binds every emulator to `0.0.0.0`, so the suite is listening, but
Windows Firewall drops the inbound connection and the phone reports
`firebase_auth/network-request-failed` — indistinguishable from a wrong address or a suite
that is not running. Run once in an **elevated** PowerShell:

```powershell
New-NetFirewallRule -DisplayName 'Mevora Firebase Emulator Suite (LAN QA)' `
  -Direction Inbound -Action Allow -Protocol TCP `
  -LocalPort 9099,8080,5001,9199,4000 `
  -Profile Private -RemoteAddress LocalSubnet
```

`-Profile Private -RemoteAddress LocalSubnet` keeps it off public networks and off the open
internet. Remove it with
`Remove-NetFirewallRule -DisplayName 'Mevora Firebase Emulator Suite (LAN QA)'`.

**2. Pick the host address.** Do not read it off `Get-NetIPAddress` alone — that lists
addresses configured on **a disconnected NIC** too, and a static address on an unplugged
Ethernet port looks exactly as plausible as the live one. Check which interface is actually
up and carrying the default route first:

```powershell
Get-NetAdapter | Select-Object Name, Status, LinkSpeed
Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Select-Object InterfaceAlias, NextHop, RouteMetric
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' }
```

Then confirm the address answers before you build against it — from the host is enough to
prove the binding, and it takes seconds:

```powershell
Invoke-WebRequest -Uri 'http://<host LAN IP>:4000' -TimeoutSec 5 -UseBasicParsing
```

Ignore `vEthernet (*)` addresses; those are Hyper-V/WSL switches the phones cannot reach.

If the live interface is Wi-Fi its address is usually DHCP, so it can change and every
installed APK then points at nothing. Give the host a DHCP reservation on the router, or
rebuild after a change. This is why the VS Code config asks for the address instead of
hardcoding it: the prompt is pre-filled but editable, so a new address costs one keystroke
rather than a file edit.

**3. Build the APK.** VS Code task **Flutter: Build two-phone QA APK (LAN)**, or:

```bash
flutter build apk --debug --flavor development \
  --dart-define=USE_EMULATORS=true \
  --dart-define=USE_AUTH_EMULATOR=true \
  --dart-define=USE_MOCK_HUMOR=false \
  --dart-define=FIREBASE_EMULATOR_HOST=<host LAN IP> \
  --dart-define=DISCOVERY_NO_DEMO=true \
  --dart-define=QA_EMAIL_A=qa_user_a@mevora.test \
  --dart-define=QA_EMAIL_B=qa_user_b@mevora.test \
  --dart-define=QA_PASSWORD=MevoraQa!2026
```

Output: `build/app/outputs/flutter-apk/app-development-debug.apk`.

**`--debug` is load-bearing, not a convenience.** `ACCESS_LOCAL_NETWORK` and
`usesCleartextTraffic` live in the *debug* source set only, so a `--profile` or `--release`
APK cannot reach the suite at all — and it fails the same way a wrong address does.

`DISCOVERY_NO_DEMO=true` matters whenever distance is under test: the hybrid repository pads a
*successful* empty deck with demo profiles in development, so a correctly empty result looks
like a broken filter.

**4. Install on both phones.** `adb devices` first, then per phone:

```bash
adb -s <serial> install -r build/app/outputs/flutter-apk/app-development-debug.apk
```

Sign in as `qa_user_a@mevora.test` on one and `qa_user_b@mevora.test` on the other.

**5. If a phone cannot connect**, check in this order — each rules out one layer:

| Check | Command | Means |
|---|---|---|
| Suite is listening on the LAN | `curl http://<host LAN IP>:4000` from another machine | binding is fine |
| Phone can reach the host | open `http://<host LAN IP>:4000` in the phone's browser | firewall and subnet are fine |
| APK carries the permission | `adb shell dumpsys package <applicationId> | grep LOCAL_NETWORK` | you built `--debug` |
| Router allows phone-to-phone/host traffic | same browser check from the *other* phone | Wi-Fi client isolation is off |
| App is using the right host | app logs, or rebuild with the define echoed | the define reached the build |

A phone browser that loads the Emulator UI while the app still fails means the build is the
problem, not the network.

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
