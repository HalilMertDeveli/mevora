# Task Completion Checklist

Run the checks that match the area touched; fix everything before reporting done.

## Always (Dart/Flutter changes)
```
flutter analyze          # must be clean; note analysis_options.yaml excludes some feature trees
flutter test             # the whole test/ tree
```
`flutter test` runs the entire `test/` tree — every `test/features/<feature>` directory
included. There is no `dart_test.yaml`; adding one with a top-level `paths:` key is blocked by
`test/test_suite_coverage_test.dart`, which also asserts CI keeps gating the whole tree.
Run a single area explicitly with `flutter test test/features/<feature>` when iterating.

## Localization changes
```
flutter gen-l10n
dart run tool/verify_generated_l10n.dart
dart run tool/verify_tr_strings.dart
```
Commit the regenerated `lib/l10n/app_localizations*.dart`.

## Cloud Functions changes
```
cd functions; npm run build; npm test
```
`npm test` runs an explicit list of `test/*.test.cjs` files (Node 20 does not glob positional
`--test` args). Add a NEW test file to that list in `functions/package.json`;
`test/testSuiteCoverage.test.cjs` fails the suite if the list and the directory drift apart.

## Firestore / Storage rules or indexes changes
```
cd firebase/tests; npm test
flutter test test/security          # security contract tests mirror the rules
```

## Before claiming a release-level change is safe
- Device E2E: `flutter test integration_test/smoke/app_launch_test.dart` (needs a connected device).
- Backend smoke: `tools/smoke/run_smoke_test.mjs` (needs a service account; hits real Firebase).

## CI parity
`.github/workflows/ci.yml` is the gate (there is no `smoke.yml`). It runs `flutter analyze` +
`flutter test test --reporter expanded` unconditionally, and — path-filtered to the areas a PR
touches — `npm ci && npm test` in `functions`, plus the Firestore/Storage emulator suite via
`npx firebase-tools@15 emulators:exec --only firestore,storage --project mevora-dev`.
CI covers the same Flutter suite as the local checklist; the local extras are the localization
verifiers, device E2E and the backend smoke harness.
