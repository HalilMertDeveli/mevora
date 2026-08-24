# Phone Number + SMS OTP

Production phone authentication for Mevora. OTP codes are created, sent, and verified only by **Firebase Authentication**. The Flutter app never generates, stores, or logs an OTP.

## Flow

1. Login → **Telefon Numarası ile Giriş Yap** / **Sign in with Phone Number**
2. Country + national number (default 🇹🇷 +90; trunk `0` OK, e.g. `0542 519 2119` → `+905425192119`)
3. Domain validation → `SendPhoneVerificationCode`
4. Firebase `verifyPhoneNumber` sends a **real carrier SMS** (Play Integrity / reCAPTCHA)
5. 6-digit OTP screen (autofill / paste)
6. `PhoneAuthProvider.credential` + `signInWithCredential`
7. Account doc `users/{uid}` is created or updated
8. Cloud Function `syncAuthAccount` sets `phoneVerified` from Admin Auth
9. Existing user with completed onboarding → Discovery; new user → Onboarding

App restart on the OTP screen: the verification session lives in memory only. If it is gone, the user is sent back to the phone screen.

## Real SMS defaults (important)

Development and production both enable app verification for real phone numbers.

| Setting | Default | Purpose |
| --- | --- | --- |
| `DISABLE_PHONE_APP_VERIFICATION` | `false` | Must stay false for carrier SMS |
| `FORCE_PHONE_RECAPTCHA` | unset → **false** | Opt in with `=true` only if Play Integrity fails on your device; needs Activity for reCAPTCHA |
| `PHONE_AUTH_TEST_NUMBER` / `PHONE_AUTH_TEST_SMS_CODE` | empty | Only used when verification is **disabled** for Console test numbers |

### Console test numbers (QA only — not production)

```bat
flutter run --flavor development -t lib/main_development.dart ^
  --dart-define=USE_EMULATORS=false ^
  --dart-define=DISABLE_PHONE_APP_VERIFICATION=true ^
  --dart-define=PHONE_AUTH_TEST_NUMBER=+905551112233 ^
  --dart-define=PHONE_AUTH_TEST_SMS_CODE=123456
```

### Real SMS (recommended)

```bat
flutter run --flavor development -t lib/main_development.dart --dart-define=USE_EMULATORS=false
```

Watch logcat / Flutter console for `[PHONE_AUTH]` stages. Debug builds also append `Firebase: <code>` under the localized error.

Do **not** use Firebase Console test numbers as a production workaround.

If Play Integrity fails on a sideloaded APK and SMS never starts:

```bat
flutter run --flavor development -t lib/main_development.dart --dart-define=USE_EMULATORS=false --dart-define=FORCE_PHONE_RECAPTCHA=true
```

(`MainActivity` extends `FlutterFragmentActivity` so reCAPTCHA can host a WebView.)

## Architecture

```
UI (PhoneLoginScreen / OtpVerificationScreen)
  → PhoneAuthController
  → Send / Verify / Resend use cases
  → AuthRepository
  → PhoneAuthService (FirebaseAuthDataSource)
  → Firebase Auth
```

States: `PhoneNumberEntering`, `SendingOtp`, `OtpSent`, `VerifyingOtp`, `PhoneAuthenticated`, `OtpError`, `SmsSendError`, `TooManyAttempts`.

**Routed screens:** `/phone` → `PhoneLoginScreen`, `/phone/otp` → `OtpVerificationScreen`

## Firebase / Android

| Item | Value |
| --- | --- |
| Firebase project | `mevora-d6ed0` |
| Android package | `com.mevora.app` |
| Billing | Blaze (required for real SMS) |
| Phone provider | Enabled |
| Debug SHA-1 | `9C:A2:E5:84:1A:55:0C:56:4B:A3:4D:0A:57:31:A5:24:AF:23:CC:9F` |
| Debug SHA-256 | `4F:D3:13:FE:A7:0A:40:AE:D4:17:B4:96:5D:1B:F4:18:33:01:BE:0E:12:75:54:64:7A:F4:BA:CB:BE:B3:E1:65` |

Release / Play App Signing SHA-1 and SHA-256 must still be added from Play Console → App integrity → App signing.

### App Check

Development uses the App Check **debug** provider. If Authentication enforces App Check, register the debug token from logcat in Firebase Console → App Check → Manage debug tokens.

## Troubleshooting (SMS does not arrive)

1. `USE_AUTH_EMULATOR=true`? → remove it
2. Package is `com.mevora.app`?
3. SHA registered on `mevora-d6ed0` Android app?
4. Phone provider enabled?
5. Blaze active?
6. `DISABLE_PHONE_APP_VERIFICATION=true` without a Console test number? → set to false for real SMS
7. App Check enforcement on? → register debug token
8. Logcat: `PhoneAuth verificationFailed code=...`
