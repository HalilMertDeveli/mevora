# Android Release Signing

Production Android releases are signed with Mevora's own upload key. The
build refuses to produce a `productionRelease` artifact unless that key is
available — it will never fall back to the debug keystore.

Nothing in this document is committed to the repository: no keystore, no
passwords, no aliases. `android/.gitignore` already ignores `key.properties`,
`**/*.jks` and `**/*.keystore`, and the repository root `.gitignore` repeats
those patterns.

## What is signed with what

| Variant | Signing |
|---|---|
| `developmentDebug`, `stagingDebug`, `productionDebug` | debug keystore |
| `developmentRelease`, `stagingRelease` | debug keystore (so `flutter run --release` works) |
| `productionRelease` | **release keystore — required, build fails without it** |

## One-time: create the upload key

Do this once, on a machine you control, and store the result in your password
manager plus an offline backup. Losing it means you can no longer update the
app on Google Play unless Play App Signing key reset is used.

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

`storeFile` may be absolute, or relative to the `android/` directory.

Then:

```bash
flutter build appbundle --flavor production --release
```

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

In all three cases `developmentDebug` and `stagingRelease` keep building.

## Verifying a signed build

```bash
flutter build appbundle --flavor production --release
keytool -printcert -jarfile build/app/outputs/bundle/productionRelease/app-production-release.aab
```

The printed certificate fingerprint must match the SHA-1/SHA-256 registered in
the Firebase Android app and in Google Play. If it does not, Google Sign-In,
Spotify OAuth and App Check will fail on store builds.
