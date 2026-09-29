# Phone Number + SMS OTP

Production phone authentication for Mevora. OTP codes are created, sent, and verified only by **Firebase Authentication**. The Flutter app never generates, stores, or logs an OTP.

## Flow

1. Login → **Telefon Numarası ile Giriş Yap** / **Sign in with Phone Number**
2. Country + national number (default 🇹🇷 +90; trunk `0` OK, e.g. `0532 123 4567` → `+905321234567`)
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
| Android package | `com.mevora.app` (Firebase app `1:821220262229:android:1a12a39a06a7516f702fdc`) |
| Billing | **An open Cloud Billing account is required.** Phone Auth SMS is not available on the Spark plan. |
| Phone provider | Enabled |
| SMS region policy | Allowlist only: `TR` |
| Debug SHA-1 | `9C:A2:E5:84:1A:55:0C:56:4B:A3:4D:0A:57:31:A5:24:AF:23:CC:9F` |
| Debug SHA-256 | `4F:D3:13:FE:A7:0A:40:AE:D4:17:B4:96:5D:1B:F4:18:33:01:BE:0E:12:75:54:64:7A:F4:BA:CB:BE:B3:E1:65` |

Release / Play App Signing SHA-1 and SHA-256 must still be added from Play Console → App integrity → App signing.

Play Integrity needs no API enabled on `mevora-d6ed0`: Firebase Authentication enables it on a Google-owned project. It needs the SHA-256 above. The reCAPTCHA fallback needs the SHA-1 and an Android API key without application restrictions. Both were true on 2026-09-29.

### Billing is checked before any SMS

A project linked to a **closed** billing account can still look normal in the Firebase console, and `billingInfo` can still report `billingEnabled: true`. The app still reaches `verifyPhoneNumber`. The backend then answers every allowed-region number with `BILLING_NOT_ENABLED` before `codeSent`, so no SMS is ever sent. On a debug build the phone screen shows:

```
SMS gönderimi için Firebase faturalandırması (Blaze) gerekli.
Firebase: billing-not-enabled
```

Check the account itself, not just the link (Cloud Billing API, as the owner):

```
GET https://cloudbilling.googleapis.com/v1/projects/mevora-d6ed0/billingInfo   → billingAccountName
GET https://cloudbilling.googleapis.com/v1/<billingAccountName>                → "open": true is required
```

On 2026-09-29 the linked account `billingAccounts/01F531-51FFB0-00D8AC` returned `"open": false`, and a send for a `+90` number returned `BILLING_NOT_ENABLED`. Reopening or relinking billing is an owner action in the Google Cloud console. No app change can work around it.

### App Check

Development uses the App Check **debug** provider. App Check is **not** enforced on Identity Toolkit (`identitytoolkit.googleapis.com` has no enforcement mode), so a missing debug token cannot stop an SMS. It only affects what runs after sign-in: callables and other enforced services answer 403. Register the token from logcat in Firebase Console → App Check → Manage debug tokens, and keep it in the gitignored `tool/app_check_debug_token.local`.

## Troubleshooting (SMS does not arrive)

First read the `Firebase: <code>` line on the phone screen (debug builds) or the `[PHONE_AUTH] VERIFICATION_FAILED code=…` line in the console. The code names the stage.

| Code | Meaning | Fix |
| --- | --- | --- |
| `billing-not-enabled` | Billing account closed or missing | Owner reopens / relinks Cloud Billing |
| `sms-region-restricted` | Country not in the SMS region policy | Authentication → Settings → SMS region policy |
| `missing-client-identifier`, `invalid-app-credential`, `app-not-authorized`, `captcha-check-failed` | Play Integrity / reCAPTCHA rejected the app | SHA-1 / SHA-256 on the Firebase Android app, package `com.mevora.app` |
| `too-many-requests`, `quota-exceeded` | Abuse protection or SMS quota | Wait; do not keep resending to the same number |
| `operation-not-allowed` | Phone provider disabled | Authentication → Sign-in method → Phone |

If `[PHONE_AUTH] CODE_SENT` appears but no SMS arrives, Firebase accepted the request. Stop changing app code and look at carrier delivery and quota instead.

Also check:

1. `USE_EMULATORS=true` together with `USE_AUTH_EMULATOR=true`? The Auth emulator never sends SMS, and the `[PHONE_AUTH] SETTINGS` line is only printed on the live path.
2. `DISABLE_PHONE_APP_VERIFICATION=true`? Then only Console test numbers work. Leave it unset for real SMS.
