# Commands

Host is Windows; default shell is PowerShell (a Git Bash tool also exists). Repo root `D:\Mevora`.

## Flutter
```
flutter pub get
flutter analyze
flutter test                      # runs the whole test/ tree (no scope restriction)
flutter test test/features/x/...  # narrow to one area while iterating
flutter gen-l10n                  # regenerate lib/l10n/app_localizations*.dart after ARB edits
```

## Running the app (flavor + entrypoint must match)
```
flutter run --flavor development -t lib/main_development.dart
flutter run --flavor staging     -t lib/main_staging.dart
flutter run --flavor production  -t lib/main_production.dart
```
Prefer the repo wrapper on Windows: `tool\flutter_run_dev.cmd` (or `tool\flutter_run_dev.ps1`).
It redirects TMP/TEMP to `<repo>\.tmp` to dodge a Windows flutter_tools `app.dill`
PathNotFoundException race, kills stale `dart` processes, auto-selects a physical USB device over an
emulator, and injects `--dart-define=SPOTIFY_CLIENT_ID=...` plus an App Check debug token read from
`tool/app_check_debug_token.local` (gitignored; not present by default).

## Cloud Functions
```
cd functions; npm install; npm run build      # tsc
cd functions; npm test                        # builds, then node --test over an explicit test list
```

## Firestore rules / moderation tests
```
cd firebase/tests; npm install; npm test
```

## Emulators
```
firebase emulators:start --only firestore,functions,storage,auth
flutter run --dart-define=USE_EMULATORS=true -t lib/main_development.dart
```

## Backend smoke (real Firebase state, needs a service account)
```
cd tools/smoke; npm install
$env:GOOGLE_APPLICATION_CREDENTIALS = "<path>"; node run_smoke_test.mjs
```

## Device E2E
```
flutter test integration_test/smoke/app_launch_test.dart      # requires a connected device
```

## Windows shell notes
- PowerShell 5.1: no `&&`/`||` chaining — use `;` or `if ($?) { ... }`.
- `gcloud` from Bash hits the Microsoft Store Python stub; call `gcloud.cmd` from PowerShell.
- Node QA/dev one-offs in `tool/` are CommonJS `.cjs`: `node tool\<name>.cjs`.
