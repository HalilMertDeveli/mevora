# Firebase security rules tests

Two layers guard `firebase/firestore.rules` and `firebase/storage.rules`.

| Layer | What it proves | Needs emulator |
|---|---|---|
| **Behavioural** — `*.security.emulator.test.mjs` | The rule actually allows/denies the operation, executed against the Firebase Emulator Suite | yes (Java) |
| **Contract** — `location.rules.test.mjs`, `test/security/*.dart` | Named guards still exist in the rules text; cheap, fast, catches accidental deletion | no |

The contract layer is supplemental only. A green contract test does **not** mean a
path is authorized correctly — during the September 2026 security audit the
contract tests passed while several real authorization defects were live. Add new
coverage to the behavioural layer.

## Running

Everything, from the repo root (Windows: use `npx.cmd`):

```bash
npx firebase emulators:exec --only firestore,storage --project mevora-rules-ci "npm --prefix firebase/tests run test:security"
```

Or the packaged script, which boots the emulators for you:

```bash
npm --prefix firebase/tests run test:emulator
```

Individual layers:

```bash
npm --prefix firebase/tests run test:contract    # no emulator, no Java
npm --prefix firebase/tests run test:pipeline    # moderation integration, no emulator
npm --prefix firebase/tests test                 # everything (inside emulators:exec)
```

First run needs `npm ci` in `firebase/tests`, plus a JDK on `PATH` for the emulators.
Nothing here ever touches a real Firebase project — `initializeTestEnvironment`
talks only to `127.0.0.1`.

## Harness

`helpers/securityHarness.mjs` gives every suite the same actor model:

| Actor | Role |
|---|---|
| `anon` | unauthenticated visitor |
| `userA` | owner / first match participant |
| `userB` | second match participant |
| `userC` | unrelated authenticated attacker |

```js
const env = await createSecurityEnv({storage: true});
const who = actorsFor(env);

await allow(who.userA.db().doc(`profiles/${UID.A}`).get());
await deny(who.userC.db().doc(`users/${UID.A}`).get());
await deny(who.anon.bucket().ref(PENDING).getDownloadURL());
```

- `seed(env, fn)` writes fixtures with rules disabled (admin privileges).
- `resetState(env, {storage})` clears both emulators — call it in `beforeEach`.
- `allow()` / `deny()` wrap `assertSucceeds` / `assertFails`.
- Fixture builders (`activeMatchAB`, `encryptedMessage`, `baseProfile`,
  `baseAccount`) keep documents shaped the way the product writes them, so a
  test failure means a rules change, not a fixture drift.

### Project ID

`createSecurityEnv()` defaults to `GCLOUD_PROJECT`, which `emulators:exec` sets.
Do not hardcode a different one: `storage.rules` resolves match membership with
`firestore.exists()`, and the Storage emulator resolves that cross-service call
against *its own* project. A mismatched ID reads an empty database and denies
every legitimate participant.

## Known-finding probes

Some probes assert the security behaviour we *want* while a verified finding is
still open. They are marked with `knownFinding(id, summary)`, which maps to
node:test's `todo`:

```js
it("client cannot write the moderation-owned profiles.photos array",
   knownFinding("B-02", "the guard trusts a client-supplied moderatedBy"),
   async () => { await deny(/* ... */); });
```

These report under `# todo` and do not fail the run, so the suite stays usable —
but the assertion stays honest and is never inverted to force a pass. When the
finding is fixed the probe turns green; **delete the `knownFinding` marker at
that point** so it becomes a hard regression test.

### Currently open

**None.** Every finding from the Agent B security audit is closed on `main`,
and the suite runs with `todo = 0`. A non-zero todo count means either a new
finding was filed or a merge silently reverted a hard assertion back to a
probe — check the breakdown by finding ID, not just the totals.

## Security programme status

All findings below are closed in merged `main` source. Each row's regression
coverage is executable, not a substring assertion.

| ID | Finding | Fix | Regression coverage |
|---|---|---|---|
| B-01 | `blocks/{blockId}` document ID not bound to the blocker | rule binds `blockId == auth.uid + '_' + blockedUserId` | `firestore.security.emulator.test.mjs` — blocks describe |
| B-02 | client could self-approve photos (`moderatedBy` trusted) | server-owned ledger `users/{uid}/photoModeration/{imageId}` + reconciling trigger | `photoModerationAuthority.test.cjs`, ledger rules probes |
| B-03 | distance trilateration oracle | active-match gate + 5 km quantisation + rate limit | `distancePrivacy.test.cjs` incl. trilateration probe |
| B-04 | privileged/entitlement fields client-writable | client-write allowlists on `users/` and `profiles/` | privileged-field + unknown-field probes |
| B-05 | LiveKit callables missing App Check | `livekitCallable` spread from `socialCallable` | `callableAppCheck.test.cjs` with control pair |
| B-07 | match-existence oracle for non-participants | `allow get` requires participation; missing and existing deny identically | match describe, outcome-equality assertion |
| B-09 | match identity / verified-badge spoofing | `matchUpdateKeysAllowed()` allowlist + per-participant map scoping | match describe, peer-forgery probes |
| B-10 | `userPrivacy/{uid}` readable by any authenticated user | owner or active non-blocked match only | privacy describe incl. rule-internal presence check |
| B-11 | `profile/thumbs/` client-writable and unmoderated | Storage writes denied; `thumbUrl` moved to the B-02 ledger | `storage.security.emulator.test.mjs`, ledger thumb tests |

### Operational follow-up — legacy forged blocks

B-01 stopped **new** forged block documents. Any malformed record written
before that rule landed would still be effective and is invisible to clients.

`runForgedBlockAudit` (admin-only callable, `functions/src/automation/`) scans
`blocks`, classifies malformed documents and files them in `adminReviewQueue`.
It is **strictly read-only** — there is no delete or repair parameter, by
design, because an ID heuristic is not sufficient grounds to remove a safety
record automatically. The lifecycle is deliberately
`DRY-RUN AUDIT -> HUMAN REVIEW -> separately authorised cleanup`.

Status: **audit mechanism implemented and locally verified. Production
execution has NOT been run and requires separate explicit authorisation.**

## Commands

```bash
# Firebase behavioural security (Firestore + Storage + legacy harness)
npx firebase emulators:exec --only firestore,storage --project mevora-rules-ci "npm --prefix firebase/tests test"

# Cloud Functions (builds first)
npm --prefix functions test

# Flutter
flutter test

# Static analysis
flutter analyze
npm --prefix functions run build
```

If another agent already holds the default emulator ports, copy `firebase.json`
to a scratch config with different `emulators` ports and pass `--config` —
do not kill the other process.
