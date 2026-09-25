# Firebase Backend Config (`firebase/`, `firebase.json`)

## Paths (non-default — rules do NOT live at repo root)
- `firebase/firestore.rules`, `firebase/storage.rules`, `firebase/firestore.indexes.json`
- `firebase/remoteconfig.defaults.json`
- `firebase/tests/` — ESM `.mjs` rules + moderation tests (`@firebase/rules-unit-testing`, `node --test`)

## Project
- Firestore `(default)` database in `eur3`.
- Hosting serves `hosting/public` with rewrites `/privacy`, `/terms`, `/guidelines`, `/help`.
- Auth providers enabled: email/password, phone, Google.
- Firebase project id and app ids are declared in `firebase.json` under `flutter.platforms`; the Dart
  side is generated into `lib/firebase_options.dart`. Staging/production separation is by flavor +
  separate Firebase projects — always confirm the `--project` before any deploy.

## Emulator ports (`firebase.json`, singleProjectMode)
auth 9099 · functions 5001 · firestore 8080 · storage 9199 · UI 4000

## Rules invariants
- Deny by default; no `if true`. Client reads are scoped to the authed uid or to explicitly shared
  match/chat documents.
- Rules changes must be paired with `firebase/tests` runs AND `test/security` (Dart contract tests
  that assert the same expectations from the app side).
- New Firestore queries usually need a composite index — add it to `firebase/firestore.indexes.json`;
  `tool/ensure_*_index.cjs` / `wait_discovery_index.cjs` help verify deployment.
- `firebase.json`, the rules files and the indexes file are high-conflict shared files under the
  multi-agent rules in `CLAUDE.md`: minimal edits, report them.
