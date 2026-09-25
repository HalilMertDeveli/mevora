# Tech Stack

## App
- Dart/Flutter, SDK constraint `sdk: ^3.11.5`; package name `mevora`, version in `pubspec.yaml`.
- Routing: `go_router` (`lib/core/routing/app_router.dart`, `app_routes.dart`, `auth_redirector.dart`).
- State: plain `ChangeNotifier` controllers + `InheritedWidget` scopes. No Riverpod/Bloc/get_it/Provider.
- Localization: Flutter gen-l10n (`l10n.yaml`, `lib/l10n/app_en.arb`, `app_tr.arb`), `generate: true`.
  Generated sources are committed under `lib/l10n/`.
- Firebase plugins: core, auth, firestore, storage, functions, messaging, crashlytics, analytics,
  app_check.
- Other notable deps: google_sign_in, sign_in_with_apple, flutter_secure_storage, cryptography (E2EE),
  geolocator, permission_handler, in_app_purchase, image_picker, rive, livekit_client (calls/video),
  record + audioplayers (voice), app_links (OAuth deep links, e.g. Spotify), flutter_idensic_mobile_sdk
  (Sumsub identity verification).
- Lints: `flutter_lints` + strict analyzer (`strict-casts`, `strict-inference`, `strict-raw-types`).

## Backend
- Cloud Functions: TypeScript 5.8, Node 20, firebase-functions v6, firebase-admin v13,
  livekit-server-sdk, google-auth-library. Compiled `tsc` → `functions/lib`, entry `lib/index.js`.
- Firestore `(default)` database, location `eur3`.
- Rules tests: `@firebase/rules-unit-testing` + `firebase` JS SDK, ESM `.mjs`, `node --test`.

## Tooling
- Package managers: `flutter pub` for Dart, `npm` for `functions/`, `firebase/tests/`, `tools/smoke/`
  (each has its own `package.json`; there is no root-level npm project).
- CI: single GitHub Actions workflow `.github/workflows/ci.yml` — `flutter analyze` + the full
  `flutter test test` suite on every PR, plus path-filtered Cloud Functions tests and the
  Firestore/Storage rules emulator suite.
