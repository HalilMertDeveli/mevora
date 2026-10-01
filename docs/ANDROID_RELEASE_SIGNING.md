# Android Release Signing

> **Before publishing:** follow `docs/GOOGLE_PLAY_PRODUCTION_LAUNCH.md` — it is the
> ordered launch checklist. Open blockers are in `docs/PUBLISH_BLOCKERS.md`.

Production Android releases are signed with Mevora's own **upload key**. The
build refuses to produce a `productionRelease` artifact unless that key is
available — it never falls back to the debug keystore — and unless it is built
from the production entrypoint.

Nothing in this document is committed to the repository: no keystore, no
passwords, no aliases. `android/.gitignore` ignores `key.properties`,
`**/*.jks` and `**/*.keystore`, and the repository root `.gitignore` repeats
those patterns.

## What is signed with what

| Variant | Signing |
|---|---|
| `developmentDebug`, `stagingDebug`, `productionDebug` | debug keystore |
| `developmentRelease`, `stagingRelease` | debug keystore — **always**, even when the upload key is configured |
| `productionRelease` | **upload key — required, the build fails without it** |

Development shares the production applicationId (`com.mevora.app`). That is why
its release build is never signed with the upload key: it would be an
uploadable store artifact wired to the development backend.

## Two keys, not one

Google Play uses **Play App Signing** for every new app. Two different keys are
involved and they have different fingerprints:

| Key | Who holds it | What it signs | Where its SHA-1 / SHA-256 comes from |
|---|---|---|---|
| **Upload key** | You (the `.jks` below) | The `.aab` you upload | `keytool -list -v -keystore mevora-upload.jks` |
| **App signing key** | Google | The APKs members actually install from Play | Play Console → Test and release → Setup → App signing |

Members' devices only ever see the **app signing key**. Every service that
pins the app to a certificate must therefore know the *app signing key's*
fingerprints, not only the upload key's. Register **both** (the upload key lets
you test a locally built release; the app signing key is what makes store
installs work):

| Where | What to register | Breaks without it |
|---|---|---|
| Firebase console → Project settings → Android app `com.mevora.app` (production project) | SHA-1 **and** SHA-256 of the app signing key, and of the upload key | Google Sign-In, phone sign-in (falls back to reCAPTCHA or fails), App Check |
| Firebase console → App Check → Play Integrity | SHA-256 of the app signing key; link the Cloud project in Play Console → App integrity | every callable (they enforce App Check) |
| After registering: re-download `google-services.json` into `android/app/src/production/` | — | the file currently has no Android OAuth client at all |
| `https://mevora.app/.well-known/assetlinks.json` (only if the `mevora.app` App Link is kept) | SHA-256 of the app signing key | the `https://mevora.app/auth/spotify` link opens the browser instead of the app; the `mevora://auth/spotify` scheme keeps working |

Spotify needs no fingerprint: the redirect is the `mevora://auth/spotify`
custom scheme, registered in the Spotify developer dashboard.

## One-time: create the upload key

Do this once, on a machine you control. Store the keystore and its passwords in
your password manager **and** in an offline backup. If the upload key is lost
you can ask Google to reset it; if it leaks, anyone can upload a build in your
name until you do.

```bash
keytool -genkeypair -v -keystore mevora-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mevora-upload
```

Keep `mevora-upload.jks` **outside** the repository working tree.

## Local release builds

Create `android/key.properties` (git-ignored) with the four values:

```properties
storeFile=C:/keys/mevora-upload.jks
storePassword=<keystore password>
keyAlias=mevora-upload
keyPassword=<key password>
```

Use an absolute `storeFile` path.

Then build from the **production entrypoint**:

```bash
flutter build appbundle --flavor production -t lib/main_production.dart --release
```

`-t lib/main_production.dart` is mandatory. The flavor only selects the native
Firebase configuration; the Dart entrypoint selects the environment, and
Flutter's default entrypoint (`lib/main.dart`) is the *development*
environment. Without `-t` the build stops with
`A production release must be built from lib/main_production.dart`.

Features that are off in release builds unless switched on at build time:

| Feature | Build flag |
|---|---|
| Humor (Mizah) | `--dart-define=HUMOR_LAB_ENABLED=true` |
| Premium paywall | `--dart-define=PREMIUM_ENABLED=true --dart-define=PREMIUM_ANDROID_PRODUCT_IDS=<productId:basePlanId,…>` |

## CI / headless builds

Instead of the properties file, set four environment variables. They take the
same values and are read only when `android/key.properties` is absent or does
not define them:

| Variable | Meaning |
|---|---|
| `MEVORA_ANDROID_KEYSTORE_PATH` | path to the `.jks` on the build machine |
| `MEVORA_ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `MEVORA_ANDROID_KEY_ALIAS` | key alias |
| `MEVORA_ANDROID_KEY_PASSWORD` | key password |

(The `key.properties` names are also accepted as Gradle properties, for
example `-PstoreFile=…`.)

On GitHub Actions, store the keystore as a base64 secret, decode it to a file
in the runner's temp directory during the job, and point
`MEVORA_ANDROID_KEYSTORE_PATH` at it. Never write it inside the checkout.

## Failure modes

The build stops as soon as the task graph is known — in seconds, not after a
full release compile — and prints why:

- **Nothing configured**
  `Production release signing is not configured. Refusing to sign a production
  release with the debug keystore.`
- **Partially configured** — the message names exactly which of the four
  values is missing, so a half-set CI secret cannot quietly disable signing.
- **Keystore file missing** — the message prints the absolute path that was
  resolved but not found.
- **Wrong entrypoint** — `A production release must be built from
  lib/main_production.dart, not lib/main.dart.`

In all cases `developmentDebug` and `stagingRelease` keep building.

At run time there is a second line of defence: `bootstrap()` shows the startup
error screen instead of starting the app when the native flavor and the Dart
environment disagree (`lib/core/config/build_guards.dart`).

## Verifying a signed build

```bash
flutter build appbundle --flavor production -t lib/main_production.dart --release
keytool -printcert -jarfile build/app/outputs/bundle/productionRelease/app-production-release.aab
```

The printed fingerprint is the **upload key's**. It must match the upload
certificate shown in Play Console → App signing. It will *not* match the app
signing key, and it is not what store-installed builds carry — see "Two keys,
not one" above.

`node tool/productionReadiness.cjs` checks the guards, the signing material
(presence only, never the values) and whether the production
`google-services.json` carries a certificate hash.
