---
description: Finish the current task, integrate it into the preview branch, verify preview, and leave the full emulator suite ready for manual QA.
---

Finalize the work in flight and hand it to the user for manual acceptance testing on the `preview` branch.

You own every routine decision here — git operations, conflict resolution, test repair, dependency fixes, emulator preparation. Do not ask for confirmation on any of them. Run the whole workflow and report once at the end.

## What this command is for

```
implementation complete
  → automated verification
  → merge into preview
  → verify preview itself
  → prepare the full emulator suite
  → push preview
  → hand off for the user's manual QA
```

`preview` is a QA/integration branch. It is where the user looks at finished work in a real running app before anyone decides whether it belongs on `main`.

**Never merge `preview` into `main`. Never open or merge a PR into `main` from this command.** The stopping point is `preview`.

## Repository facts — verify, do not assume

- Preview worktree: `D:\Mevora-worktrees\preview`, on branch `preview`. Confirm both before using it; if the path is missing or on the wrong branch, find the real one with `git worktree list` rather than creating a second preview worktree.
- `preview` regularly carries commits that are ahead of `origin/preview` and of `main`. That is legitimate integration work. Preserve it.
- The user's own worktree is `D:\Mevora`. `CLAUDE.md` makes it untouchable: never stash, reset, clean, checkout over, or change its branch. Record its state at the start and confirm it unchanged at the end.
- VS Code launch configuration: **`Mevora (development · full emulator suite)`** (`.vscode/launch.json`). It runs `lib/main_development.dart` with `USE_EMULATORS=true`, `USE_AUTH_EMULATOR=true`, and the `QA_EMAIL_A` / `QA_EMAIL_B` / `QA_PASSWORD` defines already filled in. Use it; do not invent a parallel setup.

## Phase 1 — Identify the work

Establish the repository, current worktree, branch, HEAD, `git status`, upstream state, and the state of `preview`. Confirm the work is Mevora's.

If the working tree holds changes unrelated to the task, isolate the task instead of sweeping them in. Preserve them. `git reset --hard` and `git clean -fd` are last resorts and only when you can show nothing is lost.

## Phase 2 — Finish the task before touching preview

Verify the implementation is actually complete: the code, the changed files, tests, analyzer, generated files, Cloud Functions, Firestore rules and indexes where relevant.

Run verification targeted at what changed — `flutter analyze` on the touched scope, the affected Flutter tests, the Functions suite, the rules suite. This is the end of a task, so run enough to establish the feature works; it is not an excuse to run everything after every small edit.

A failing test that you can fix is not a reason to stop. Investigate, fix, retest.

## Phase 3 — Commit and push the source branch

Read the diff before committing. Commit only what belongs to this task, with a conventional-commit subject and a body that explains why the change exists, not what the diff already shows.

Push, then confirm local HEAD matches the remote. If the commits are already pushed, do not manufacture an empty commit.

## Phase 4 — Prepare preview

`git fetch origin`. Locate and validate the preview worktree. Inside it, confirm the branch is `preview` and reconcile it with `origin/preview` without discarding preview-only work.

## Phase 5 — Integrate

Merge the source branch into `preview`. Prefer an ordinary merge that keeps history readable.

Resolve conflicts yourself. Read both sides, understand why they diverged, and keep the behaviour both sides intended. Never take `ours` or `theirs` wholesale to make a conflict disappear — a conflict in `functions/package.json`'s test list, for example, is almost always a union, and dropping either side breaks `testSuiteCoverage`. Re-verify after resolving; a conflict resolution that compiles is not the same as one that is correct.

## Phase 6 — Verify preview itself

The source branch passing is not enough. Run verification **from the preview worktree**, because integration is where things break.

`flutter pub get` if dependencies moved, then `flutter analyze`, the relevant Flutter tests, the Functions suite, and the rules suite. Widen beyond the touched scope here — this is the integration gate, and regressions that only appear after a merge are exactly what it exists to catch.

If something fails only after merging, fix it. Put the fix wherever it genuinely belongs: a real product fix belongs on the source branch and flows through; an integration-only fix can land on `preview`. Either way leave the history explainable. Never leave `preview` knowingly broken.

## Phase 7 — Prepare the full emulator suite

The user's next step is running the app against the local Firebase Emulator Suite. Make that possible; do not replace the existing setup.

The launch configuration starts the app but **not** the emulators. They come up separately, and the sequence is documented in the header of `tool/seedEmulatorQaUsers.cjs`:

1. `firebase emulators:start --config firebase.qa.json --only auth,firestore,functions --project mevora-d6ed0`

   `firebase.qa.json`, not the default config — it binds `0.0.0.0` so an Android emulator can reach the host. Also make sure `functions/` has `node_modules` and a built `lib/`, or the Functions emulator refuses to start and every Discover/Boost result is meaningless.

2. Seed the QA users:
   ```
   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
     node tool/seedEmulatorQaUsers.cjs
   ```

3. The user presses F5 on `Mevora (development · full emulator suite)`.

Where you can do so safely, confirm the emulators start and the seed succeeds. If project scripts already run smoke tests against the suite, run the relevant ones. Do not touch production data to prepare local QA.

## Phase 8 — Push preview

Push `preview` to origin and confirm local and remote HEAD match. Report the SHA.

## Phase 9 — Hand off

Leave the preview worktree clean and understandable. Tell the user the exact command to start the emulators and that F5 on the named configuration runs the app. Do not invent extra steps.

## Failure policy

Keep going through fixable engineering problems: analyzer errors, failing tests, dependency resolution, a stale branch, an ordinary merge conflict, emulator config that needs a small repair, generated files that need regenerating.

```
audit → fix → test → retest → continue
```

Stop only for something genuinely external: credentials that cannot be produced locally, a third-party service that is down, a device- or store-only check that cannot be emulated, or ambiguity where continuing risks losing the user's work. If you are blocked, finish every independent step that can still be completed, then say precisely what blocked you.

## What must not happen

1. `preview` merged into `main`, or a PR opened into `main`.
2. Claiming the user's manual QA was performed. It was not.
3. Two-user runtime behaviour reported as verified unless two emulators actually exercised it.
4. Unrelated local changes destroyed.
5. A fixable failing test abandoned.
6. `preview` left broken.
7. Stopping after the merge without verifying the merged result.
8. A second, competing emulator or launch setup.

## Final report

```
PREVIEW FINALIZATION
====================

SOURCE BRANCH:
SOURCE SHA:

TARGET:
preview

PREVIEW SHA:
ORIGIN/PREVIEW SHA:

MERGE:               PASS / FAIL
FLUTTER ANALYZE:     PASS / FAIL
TARGETED TESTS:      PASS / FAIL
PREVIEW REGRESSION:  PASS / FAIL
FULL EMULATOR SUITE: READY / BLOCKED
PREVIEW PUSH:        PASS / FAIL

WORKTREE:
D:\Mevora-worktrees\preview

MANUAL QA:
READY

NEXT ACTION FOR USER:
Start the emulator suite, then open the preview worktree and run
"Mevora (development · full emulator suite)".

MAIN MODIFIED:       NO
USER WORKTREE:       UNTOUCHED

BLOCKERS:
None
```

Follow it with the commits that matter, the tests you actually ran with their counts, any fix you made during integration and why, and the specific things worth the user's attention when they test by hand.
