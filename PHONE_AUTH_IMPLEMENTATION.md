# Phone Number + SMS OTP

Production phone authentication for Mevora. OTP codes are created, sent, and verified only by **Firebase Authentication**. The Flutter app never generates, stores, or logs an OTP.

## Flow

1. Login → **Telefon ile devam et**
2. Country + national number (default 🇹🇷 +90)
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

### Enable Phone provider

Firebase Console → Authentication → Sign-in method → **Phone** → Enable, for:

- `mevora-dev`
- `mevora-staging`
- `mevora-production`

Test phone numbers belong only in the Firebase Console (or emulator config), never in app source.

### Real SMS vs Auth emulator

The Auth emulator **never sends SMS**. Development therefore uses **live Phone Auth on `mevora-dev`** unless you opt in:

| Goal | Command |
| --- | --- |
| Real SMS (default `flutter run` development) | Live Auth. Firestore emulator still used unless `USE_EMULATORS=false`. |
| Physical device (recommended for SMS) | `flutter run --flavor development -t lib/main_development.dart --dart-define=USE_EMULATORS=false` |
| Auth emulator / no SMS | `--dart-define=USE_AUTH_EMULATOR=true` and start the Auth emulator |

Android `10.0.2.2` only reaches the host from the **Android emulator**. On a real phone it is a black hole — use `USE_EMULATORS=false` or `--dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1` plus `adb reverse`.

Real SMS also requires Console steps: Phone provider enabled, SMS region allows TR (already set on `mevora-dev`), and **Blaze billing**. Spark cannot send SMS to real numbers.

### Android SHA certificates

Phone Auth requires the app’s SHA-1 and SHA-256 on the Android app in Firebase.

Debug keystore (this machine):

```bat
"C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

Observed debug fingerprints:

- SHA-1: `9C:A2:E5:84:1A:55:0C:56:4B:A3:4D:0A:57:31:A5:24:AF:23:CC:9F`
- SHA-256: `4F:D3:13:FE:A7:0A:40:AE:D4:17:B4:96:5D:1B:F4:18:33:01:BE:0E:12:75:54:64:7A:F4:BA:CB:BE:B3:E1:65`

Debug hashes are already registered on:

- `com.mevora.app.dev` (`mevora-dev`)
- `com.mevora.app.staging` (`mevora-staging`)
- `com.mevora.app` (`mevora-production`)

Firebase MCP cannot enable the Phone sign-in provider (`firebase_init` auth schema has no Phone field). Enable it in Console for each project:

Authentication → Sign-in method → Phone → Enable.

Release / Play App Signing SHA-1 and SHA-256 still need to be added from Play Console (App integrity → App signing) onto the production Android app. Debug hashes are not a substitute for Play signing certificates.

### iOS

- Enable Push Notifications and upload APNs key/cert for silent verification.
- If APNs is unavailable, Firebase falls back to reCAPTCHA.
- App Check (already bootstrapped) stays compatible: debug providers in development, Play Integrity / DeviceCheck in production.

### Rate limits

The 60-second resend countdown is UX only. Firebase abuse protection and quota are authoritative. Invalid OTP limits are also enforced by Firebase.

## Testing

- Unit: `PhoneNumberValidator`, `E164Formatter`, send/verify/resend use cases, `PhoneAuthController`
- Widget: phone screen, country selector, OTP boxes, resend copy, errors, loading
- Integration tests use repository mocks and must not send real SMS in CI
- Emulator test numbers: Firebase Console only

## Production checklist

- [x] Debug SHA-1 and SHA-256 on Android apps for dev, staging, and production
- [ ] Play App Signing SHA-1 and SHA-256 on production Android
- [ ] Phone provider enabled on dev, staging, production (Console only; MCP has no Phone field)
- [ ] Blaze billing on each project that must send real SMS
- [x] SMS region allow-list includes TR (and the in-app country catalog) on `mevora-dev`
- [ ] Same SMS region policy on staging and production
- [ ] iOS APNs configured
- [x] No test numbers in source
- [ ] `syncAuthAccount` deployed
- [x] Firestore rules: other users cannot read `users/{uid}`
- [x] `flutter analyze` and `flutter test` clean
