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
- [ ] iOS APNs configured
- [x] No test numbers in source
- [ ] `syncAuthAccount` deployed
- [x] Firestore rules: other users cannot read `users/{uid}`
- [x] `flutter analyze` and `flutter test` clean
