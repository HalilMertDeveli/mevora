# Phone Number + SMS OTP

Production phone authentication for Mevora. OTP codes are created, sent, and verified only by **Firebase Authentication**. The Flutter app never generates, stores, or logs an OTP.

## Flow

1. Login → **Telefon Numarası ile Giriş Yap** / **Sign in with Phone Number**
2. Country + national number (default 🇹🇷 +90; trunk `0` OK, e.g. `0542 519 2119` → `+905425192119`)
3. Domain validation → `SendPhoneVerificationCode`
4. Firebase `verifyPhoneNumber` sends the SMS
5. 6-digit OTP screen (autofill / paste)
6. `PhoneAuthProvider.credential` + `signInWithCredential`
7. Account doc `users/{uid}` is created or updated
8. Cloud Function `syncAuthAccount` sets `phoneVerified` from Admin Auth
9. Existing user with completed onboarding → Discovery; new user → Onboarding

App restart on the OTP screen: the verification session lives in memory only. If it is gone, the user is sent back to the phone screen. That is not treated as “SMS sent”.

## Architecture

```
UI (PhoneLoginScreen / OtpVerificationScreen)
  → PhoneAuthController
  → Send / Verify / Resend use cases
  → AuthRepository
  → PhoneAuthService (FirebaseAuthDataSource)
  → Firebase Auth
```

No `FirebaseAuth.instance` in widgets or domain.

States: `PhoneNumberEntering`, `SendingOtp`, `OtpSent`, `VerifyingOtp`, `PhoneAuthenticated`, `OtpError`, `SmsSendError`, `TooManyAttempts`.

**Routed screens (use these):**
- `/phone` → `PhoneLoginScreen`
- `/phone/otp` → `OtpVerificationScreen`

**Legacy (not registered in the router):**
- `PhoneSignInPage` / `OtpVerificationPage` — kept for reference; do not wire without cleanup.

## How OTP never leaves Firebase

- Flutter does not generate a code.
- The SMS code is typed (or autofilled) and passed once into `PhoneAuthProvider.credential`.
- It is not written to Firestore, SharedPreferences, analytics, Crashlytics, or logs.
- `AppLogger` redacts E.164 numbers and token-like values.
- Analytics events are names only: `phone_auth_started`, `otp_sent`, `otp_verified`, `phone_auth_failed`, `otp_resend`, `otp_verification_failed`.
- `phoneVerified=true` is never set by the client. `syncAuthAccount` copies it from `admin.auth().getUser(uid).phoneNumber`.

## Privacy

`phoneNumber`, `authProviders`, `phoneVerified`, `email`, and timestamps live on **`users/{uid}`** (owner read/write). They are forbidden on `profiles/{uid}` and must never appear in discovery, chat, or match payloads.

Linking Google / Apple / Spotify is explicit. Email match does **not** auto-merge accounts.

## Firebase / Android / iOS

### Active development project

| Item | Value |
| --- | --- |
| Firebase project | `mevora-d6ed0` |
| Android package (development flavor) | `com.mevora.app` (no `.dev` suffix) |
| Staging package | `com.mevora.app.staging` |
| Production package | `com.mevora.app` |

Development builds target **live Auth on `mevora-d6ed0`**. Do not confuse with older docs that mentioned `mevora-dev` / `com.mevora.app.dev`.

### Enable Phone provider

Firebase Console → Authentication → Sign-in method → **Phone** → Enable, for each project.

On `mevora-d6ed0` this is already **enabled** (verified via Identity Toolkit Admin API). Staging/production still need the same check if those projects are used for SMS.

Test phone numbers belong only in the Firebase Console (Authentication → Settings → Phone numbers for testing), never in app source.

Example Console test number on `mevora-d6ed0`: `+905551112233` / code `123456`.

### Real SMS vs Auth emulator

The Auth emulator **never sends SMS**. Development therefore uses **live Phone Auth on `mevora-d6ed0`** unless you opt in:

| Goal | Command |
| --- | --- |
| Real / test SMS (recommended) | `flutter run --flavor development -t lib/main_development.dart --dart-define=USE_EMULATORS=false` |
| Emulator + live Auth (no Auth emulator) | Same as above, or omit `USE_AUTH_EMULATOR` (default is live Auth) |
| Auth emulator / no SMS | `--dart-define=USE_AUTH_EMULATOR=true` and start the Auth emulator |

Android `10.0.2.2` only reaches the host from the **Android emulator**. On a real phone it is a black hole — use `USE_EMULATORS=false` or `--dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1` plus `adb reverse`.

Real SMS also requires Console steps: Phone provider enabled, SMS region allow-list (in-app country catalog, including TR), and **Blaze billing**. Spark cannot send SMS to real numbers. Console **test numbers** work without delivering a carrier SMS.

### Android SHA certificates

Phone Auth requires the app’s SHA-1 and SHA-256 on the Android app in Firebase (`mevora-d6ed0` → `com.mevora.app`).

Debug keystore (this machine):

```bat
"C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

Observed debug fingerprints (registered on `com.mevora.app` in `mevora-d6ed0`):

- SHA-1: `9C:A2:E5:84:1A:55:0C:56:4B:A3:4D:0A:57:31:A5:24:AF:23:CC:9F`
- SHA-256: `4F:D3:13:FE:A7:0A:40:AE:D4:17:B4:96:5D:1B:F4:18:33:01:BE:0E:12:75:54:64:7A:F4:BA:CB:BE:B3:E1:65`

The same debug hashes are also present on the legacy `com.mevora.app.dev` Android app entry in `mevora-d6ed0` (unused by current development flavor).

Firebase MCP cannot enable the Phone sign-in provider via the plugin alone; Identity Toolkit Admin API / Console can. On `mevora-d6ed0` Phone is enabled.

Authentication → Sign-in method → Phone → Enable (other projects).

Release / Play App Signing SHA-1 and SHA-256 still need to be added from Play Console (App integrity → App signing) onto the production Android app. Debug hashes are not a substitute for Play signing certificates.

### App Check + phone verification (development)

1. Activates **App Check debug providers**. If App Check enforcement is ON for Authentication, register the debug token from logcat in Firebase Console → App Check → Manage debug tokens.
2. Sets `appVerificationDisabledForTesting: true` by default in development so Console test numbers and debug sideloads are not blocked by Play Integrity / reCAPTCHA.
3. Registers the Console test pair `+905551112233` / `123456` via `setSettings(phoneNumber:, smsCode:)` for automatic retrieval in development.
4. Removed empty `android:taskAffinity=""` from `MainActivity` — it broke reCAPTCHA Custom Tab returns (`about:blank`).
5. Production keeps app verification enabled. To exercise real verification in development: `--dart-define=DISABLE_PHONE_APP_VERIFICATION=false`.

### User-facing errors

`AuthErrorMapper` + `L10nErrors.auth` map Firebase codes to safe copy (never raw `firebase_auth/` strings), including:

- `billing-not-enabled` / status `17499` → Blaze required
- `invalid-verification-code` → invalid OTP
- `invalid-app-credential` / `captcha-check-failed` / Play Integrity → app verification
- `sms-region-restricted` → SMS failed
- `quota-exceeded` / `too-many-requests` → quota / too many attempts
- `unavailable` / `internal` (without billing hint) → temporarily unavailable

## Testing

- Unit: `PhoneNumberValidator`, `E164Formatter`, send/verify/resend use cases, `PhoneAuthController`
- Widget: phone screen, country selector, OTP boxes, resend copy, errors, loading
- Integration tests use repository mocks and must not send real SMS in CI
- Emulator test numbers: Firebase Console only

### Smoke test (manual)

1. Use Console test number on `mevora-d6ed0`: national `0555 111 22 33` with 🇹🇷 +90 (maps to `+905551112233`) / code `123456`.
2. Run with `USE_EMULATORS=false` (Auth emulator off).
3. Login → **Telefon Numarası ile Giriş Yap** → enter test national number → OTP screen → enter Console code → signed in.

## Production checklist

- [x] Debug SHA-1 and SHA-256 on `com.mevora.app` for `mevora-d6ed0`
- [ ] Play App Signing SHA-1 and SHA-256 on production Android
- [x] Phone provider enabled on `mevora-d6ed0` (Identity Toolkit `signIn.phoneNumber.enabled`)
- [x] Blaze billing enabled on `mevora-d6ed0` (required for real SMS)
- [x] SMS region ALLOW list includes TR and the in-app country catalog on `mevora-d6ed0`
- [ ] Same SMS region policy on staging and production
- [ ] iOS APNs configured
- [x] No test numbers in source (Console test number `+905551112233` / `123456` registered on `mevora-d6ed0` only)
- [ ] `syncAuthAccount` deployed
- [x] Firestore rules: other users cannot read `users/{uid}`
- [x] `flutter analyze` and `flutter test` clean

## Troubleshooting (SMS does not arrive)

1. `USE_AUTH_EMULATOR=true`? → remove it
2. Package is `com.mevora.app`? (development has no `.dev` suffix)
3. SHA registered on `mevora-d6ed0` Android app `com.mevora.app`?
4. Phone provider enabled on this project?
5. Blaze active for real SMS? (test numbers do not need carrier SMS)
6. App Check enforcement on? → register debug token from logcat
7. Logcat: `PhoneAuth verificationFailed code=...` / `billing-not-enabled` / `invalid-app-credential`?
