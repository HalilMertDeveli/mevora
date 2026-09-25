# Cloud Functions (`functions/`)

TypeScript → `tsc` → `lib/`, entry `lib/index.js`, Node 20, firebase-functions v6 / firebase-admin v13.
Single deploy codebase `default` (see `firebase.json`).

## Layout (`functions/src/`)
- `index.ts` — export surface for every deployed function. HIGH-CONFLICT shared file: append, do not
  reorganize.
- `backend.ts` — shared admin/init helpers.
- Domain modules (flat files): `discoveryMatching.ts`, `discoveryFallback.ts`, `discoveryActivity.ts`,
  `matchScore.ts`, `relationshipMatch.ts`, `relationshipCompatibility.ts`, `musicCompatibility.ts`,
  `spotifyAuth.ts` / `spotifyConfig.ts` / `spotifyMusic.ts`, `incomingLikes.ts`(+`Shape`),
  `messageRateLimit.ts`, `profileSafety.ts`, `premium.ts`, `notifications.ts`, `onboarding.ts`,
  `social.ts`, `language.ts`, `deleteAccount.ts`, `ids.ts`.
- Subfolders: `automation/`, `boost/`, `compatibility/`, `moderation/`, `music/`, `security/`,
  `sumsub/`, `smoke/`.

## Tests
- `functions/test/*.test.cjs`, run by `node --test` via `npm test` (which builds first, so tests
  exercise compiled `lib/`, not `src/`).
- The test file list is hardcoded in the `test` script in `package.json` — new suites must be added
  there explicitly.

## Invariants
- Server owns trust: compatibility/match scoring, moderation decisions, premium entitlement, rate
  limits and Sumsub verification are decided here, never on the client.
- Secrets (Spotify, Sumsub, LiveKit) come from Firebase config/env, never from committed files.
