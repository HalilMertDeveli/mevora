# Mevora

Mevora is a Flutter dating application for iOS and Android. The product helps people discover compatible connections, not simply people nearby.

**Package ID:** `com.mevora.app`  
**Current phase:** Phase 2 — Firebase Configuration

## Environments

| Flavor | Dart entrypoint | Android / iOS id | Firebase project |
| --- | --- | --- | --- |
| development | `lib/main_development.dart` | `com.mevora.app.dev` | `mevora-dev` |
| staging | `lib/main_staging.dart` | `com.mevora.app.staging` | `mevora-staging` |
| production | `lib/main_production.dart` | `com.mevora.app` | `mevora-production` |

Development always uses the Firebase Emulator Suite. It must never read or write staging or production data.

## Run

Start emulators, then the Android development flavor:

```bash
npx.cmd -y firebase-tools@latest emulators:start --project mevora-dev
flutter run --flavor development -t lib/main_development.dart
```

```bash
flutter run --flavor staging -t lib/main_staging.dart
flutter run --flavor production -t lib/main_production.dart
```

## Verify

```bash
flutter analyze
flutter test
```

Development follows `MEVORA_DEVELOPMENT.md`. Do not skip phases.
