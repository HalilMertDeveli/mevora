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
it("a third party cannot create a block document naming two other users",
   knownFinding("B-01", "blocks/{blockId} create does not bind the document ID to blockerId"),
   async () => { await deny(/* ... */); });
```

These report under `# todo` and do not fail the run, so the suite stays usable —
but the assertion stays honest and is never inverted to force a pass. When the
finding is fixed the probe turns green; **delete the `knownFinding` marker at
that point** so it becomes a hard regression test.

Currently open (see the Agent B security audit):

| ID | Area |
|---|---|
| B-01 | `blocks/{blockId}` document ID is not bound to `blockerId` |
| B-02 | client writes the moderation-owned `profiles.photos` array |
| B-04 | entitlement/trust fields writable on `users/` and `profiles/` |
| B-07 | match-existence oracle for non-participants |
| B-09 | `matches` update freeze-list is not `hasOnly` |
| B-10 | `userPrivacy/{uid}` readable by any authenticated user |
| B-11 | `profile/thumbs/` is client-writable, unmoderated, world-readable |
