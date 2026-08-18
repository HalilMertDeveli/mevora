# Mevora Localization Architecture

Supported UI languages: **Turkish (`tr`)** and **English (`en`)** only. There is no third language.

## Detection and priority

On first launch there is no saved preference. Mevora reads the device locale (`PlatformDispatcher` / Flutter `Locale`):

- `tr` / `TR` → Turkish
- **any other** device language (`en`, `de`, `fr`, …) → English

After that, language resolution is always:

1. User’s saved manual language (`tr` | `en`) in local storage
2. Device language (same tr-vs-else rule)
3. English default

`LanguageController.load()` persists the first detected language so restart is stable.

Login, splash, and Firebase-unavailable screens use this resolved locale **before auth**. They never wait for Firestore.

## Manual select

Settings → Account (`AccountSettingsPage`) includes `LanguageSettingsSection`.

Radio options:

- Türkçe 🇹🇷
- English 🇬🇧

Tapping a language calls `LanguageController.setLanguage`. `MaterialApp.locale` is bound to the controller via `ListenableBuilder`, so the UI switches **without an app restart**.

Widgets do not contain language logic. They only call `AppLocalizations.of(context)`.

## Local storage

`SharedPreferencesLanguageDataSource` writes `mevora.languageCode` (`tr` or `en`).

Local storage is the source of truth for **fast startup**. Logout **does not** reset language to the device default.

## Firebase sync

After login, `LanguageController.attachUser(uid)` writes `userSettings/{uid}.languageCode` (and a `language` alias for older readers).

- Local write always happens first and always applies to the UI
- Firestore is best-effort; a failed or offline write **does not** roll back the UI
- Offline language switch works
- `detachUser()` on logout clears the uid only

Cloud Functions that send push copy read `userSettings/{uid}.languageCode` (fallback `language`). Missing or unknown → English.

## ARB

```text
lib/l10n/app_en.arb   # template
lib/l10n/app_tr.arb
l10n.yaml
```

`pubspec.yaml` enables `flutter: generate: true` with `flutter_localizations` and `intl`.

Generated lookup only knows `en` and `tr`. `AppLanguage.fromDeviceLocale` / `fromCode` always maps the MaterialApp locale to one of those two so missing-locale lookup cannot crash. Missing ARB keys fail at generate time against the English template.

Copy is dating-app natural language, not word-for-word machine translation.

## Flutter architecture

```text
Widgets
  → AppLocalizations.of(context)
LanguageSettingsSection
  → LanguageController
    → LanguageRepository
      → LocalLanguageDataSource (SharedPreferences)
      → UserSettingsRepository (Firestore, after login)
```

`FirebaseAuth.setLanguageCode` is bound so Phone Auth SMS follows the UI language. Flutter never generates OTP codes.

Dates, times, numbers, and distance use `intl` / `L10nFormat` for the active locale. The database stores `Timestamp` / UTC, never display strings like `18.08.2026`.

Distance examples:

- TR: `2 km uzakta`, `2,5 km uzakta`
- EN: `2 km away`, `2.5 km away`

Auth / purchase / location errors map `*ErrorKind` → localized strings in `L10nErrors` (invalid OTP → TR `Doğrulama kodu geçersiz.` / EN `Invalid verification code.`).

Analytics may include `languageCode` only. No extra PII.

## Notifications

`functions/src/notifications.ts` picks TR/EN bodies from `userSettings.languageCode`, e.g. TR `Yeni bir eşleşmen var!` / EN `You have a new match!`.

## Security

`userSettings/{uid}` is **owner-only** read/write. `languageCode`, when present, must be `tr` or `en`.

## Testing

Covered in `test/core/localization/` and widget tests:

- Device TR / EN / DE with no saved preference
- Saved `tr` / `en` wins over device
- Manual change + restart
- Logout keeps local preference
- Login syncs Firebase
- Offline / Firebase failure still applies local UI
- Unsupported locale maps to English
- Long EN/TR strings on buttons and Boost
