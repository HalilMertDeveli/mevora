# Mevora — Parallel Agent Development Standard

Applies to **every** development, bug-fix, audit, test, performance, security, release and
maintenance task in this repository. Multiple AI agents may work on Mevora simultaneously.
Parallel execution is allowed **only** when each agent is properly isolated.

> Supersedes `docs/multi-agent-git-workflow.md`. Where the two disagree, this file wins.

---

## Core rule

**ONE AGENT = ONE TASK = ONE BRANCH = ONE WORKTREE**

- Never let two active agents change the same Git worktree.
- Never continue development directly inside another agent's branch.

Every meaningful independent task gets: its own branch, its own worktree, a defined scope,
a known base commit, an explicit file-ownership area, its own tests, its own commit(s),
its own push, and its own PR-ready result.

---

## Agent identity

Every prompt defines:

```
AGENT:            <short agent/task name>
TASK TYPE:        IMPLEMENTATION | BUG FIX | AUDIT | TEST | SECURITY | PERFORMANCE | RELEASE
BASE:             origin/main, or an explicitly named dependency branch
BRANCH:           <meaningful branch name>
WORKTREE:         <dedicated worktree path>
```

Example: `Security Auditor` / `AUDIT` / `origin/main` / `audit/firebase-security` / `../mevora-security-audit`

---

## Worktree isolation

Before any modification:

1. Fetch the latest required base.
2. Verify the exact base SHA.
3. Inspect the user's current worktree.
4. **Do not modify the user's existing dirty worktree.**
5. Create a separate worktree for this task.
6. Create or check out only the assigned branch inside that worktree.

```
mevora/                          user's original worktree
../mevora-agent-stabilization/   fix/single-device-stabilization
../mevora-agent-security/        audit/firebase-security
../mevora-agent-performance/     audit/performance-cost
../mevora-agent-admin/           audit/admin-moderation
```

Agents never share a worktree.

### The user's worktree is untouchable

If it is dirty, do **not** stash, reset, clean, check out over, commit, or otherwise modify it.
Leave it completely alone.

### Pre-flight report

Report before starting work:

```
BASE SHA:
BRANCH:
WORKTREE:
USER WORKTREE STATUS:
TASK SCOPE:
EXPECTED FILE OWNERSHIP:
KNOWN DEPENDENCIES:
PARALLEL SAFETY:
```

---

## Parallel safety classification

Classify every task before implementing.

| Class | Meaning | Examples |
|---|---|---|
| **SAFE_PARALLEL** | Little or no overlap; may run simultaneously | security / performance / admin / documentation / store-readiness audits |
| **CONTROLLED_PARALLEL** | Only if file ownership and dependencies are clearly separated | localization fixes, notification routing, data export, photo handling, premium infrastructure |
| **SERIAL_REQUIRED** | Must not run while another agent changes the same runtime behavior; freeze the subsystem until testing finishes | two-device core dating acceptance, matching changes, realtime chat, E2EE, final production acceptance |

---

## File ownership

Every implementation prompt declares:

```
PRIMARY OWNERSHIP:   - <folder/file>
SHARED FILES:        - <central file>
DO NOT TOUCH:        - <unrelated area>
```

Start inside PRIMARY OWNERSHIP. Expand only when a real dependency requires it.

### High-conflict shared files

Treat as shared infrastructure:

```
pubspec.yaml                    functions/src/index.ts
pubspec.lock                    app_router.dart
firestore.rules                 bootstrap.dart
storage.rules                   shared DI/bootstrap files
firebase.json                   localization ARB files
android/app/build.gradle.kts    GitHub Actions workflows
AndroidManifest.xml
```

Before modifying one:

1. Determine whether another active task may also modify it.
2. Minimize the edit.
3. Do not reformat unrelated sections.
4. Report the shared-file modification explicitly.
5. Include it in the final merge-risk report.

No cleanup or refactor changes in shared files unless the task requires it.

---

## Dependencies

Every prompt declares:

```
BLOCKED BY:                     <task or NONE>
BLOCKS:                         <task or NONE>
CAN RUN IN PARALLEL WITH:       <tasks>
MUST NOT RUN IN PARALLEL WITH:  <tasks>
```

### Base branch rule

Default base is **`origin/main`** — do not assume the user's currently checked-out branch.
If a task depends on an unmerged branch, declare `DEPENDENCY BRANCH:` and its `BASE SHA:`
explicitly. Never silently stack branches.

### Stale base protection

Run `git fetch origin` before implementation and again before the final push. Compare the
task base against current `origin/main`. If main moved, do **not** auto-rebase or auto-merge —
judge whether the new commits affect this task and report:

```
BASE STATUS: CURRENT | STALE-BUT-SAFE | REBASE-RECOMMENDED | CONFLICT-RISK
```

Never force rebase. Never force push.

---

## Workflows by agent type

**Audit agents** — read-only first (`audit/firebase-security`, `audit/performance-cost`,
`audit/admin-moderation`, `audit/privacy-gdpr`):

```
AUDIT → VERIFY → CLASSIFY → PRIORITIZE → REPORT
```

Do not fix every discovered issue inside the audit branch. Propose a separate branch per
confirmed issue (`fix/security-chat-access`, `perf/discovery-read-cost`,
`fix/privacy-data-export`). This prevents giant mixed branches.

**Implementation agents** — one logical change per agent:

```
AUDIT → REPRODUCE → IMPLEMENT → TARGETED TEST → FIX → RETEST
→ FULL RELEVANT TEST → VERIFY DIFF → COMMIT → PUSH → REPORT
```

**Test / acceptance agents** — test a stable integration snapshot. While a test agent runs,
no other agent may modify the subsystem under test. Read-only audits may continue.

---

## QA integration branch

Never merge parallel feature/fix branches into each other just to test them. Create a
disposable local integration branch instead, e.g. `qa/integration-2026-09-21`.

- Local and test-only unless explicitly requested otherwise
- Not a product branch, not a permanent source branch
- Do not push unless explicitly needed; never merge into main
- Individual task branches remain the source of truth

Use it for: `flutter analyze`, `flutter test`, Functions tests, Firebase rules tests,
builds, emulator acceptance.

---

## Merge order

Each task reports its dependencies and a recommended merge order. **Never merge
automatically** — the user reviews and decides.

---

## Final report

```
AGENT:
TASK:
STATUS:

BASE SHA:
BRANCH:
WORKTREE:

FILES CHANGED:
SHARED FILES CHANGED:

TESTS:
COMMIT:
PUSH:
PR:

BLOCKED BY:
BLOCKS:

PARALLEL CONFLICT RISK:   LOW | MEDIUM | HIGH
CONFLICT DETAILS:
RECOMMENDED MERGE ORDER:

USER ORIGINAL WORKTREE:   UNTOUCHED | NOT UNTOUCHED
```

---

## Global git rules — do not

- work directly on `main`
- share a worktree with another agent
- overwrite the user's working tree
- commit unrelated modifications
- stash, discard or reset user changes
- force push
- merge PRs automatically, or close unrelated PRs
- combine unrelated fixes into one branch
- copy entire stale branches into current work
- run repo-wide formatting without explicit need

---

## Context control

Start with the smallest relevant file set; expand only when a real dependency requires it.
Do not load `build/`, `.dart_tool/`, `node_modules/`, generated output, large logs,
unrelated documentation, or unrelated feature folders. Do not repeatedly repo-scan —
reuse previously verified information while it is still current.

### Code navigation

Serena MCP is onboarded for this repository. Prefer its semantic tools over broad reads and scans:

- Read `mem:core` first; it is the entry point to `mem:tech_stack`, `mem:suggested_commands`,
  `mem:conventions`, `mem:task_completion`, `mem:functions/core`, `mem:firebase/core`.
- Discovery: `get_symbols_overview` / `find_symbol` instead of reading whole Dart files;
  `find_referencing_symbols` instead of grepping for call sites.
- Glob and Grep stay fine for locating files; follow-up reads should be symbolic.
- Use Context7 for up-to-date Flutter/Firebase/package documentation instead of guessing API shapes.

---

## Standard prompt structure

```
# TASK

AGENT:
TASK TYPE:

PARALLEL EXECUTION:
BASE:
BRANCH:
WORKTREE:

DEPENDENCIES:
BLOCKED BY:
BLOCKS:
CAN RUN IN PARALLEL WITH:
MUST NOT RUN IN PARALLEL WITH:

FILE OWNERSHIP:
PRIMARY OWNERSHIP:
SHARED FILES:
DO NOT TOUCH:

GOAL:
SCOPE:
CURRENT BEHAVIOR:
EXPECTED BEHAVIOR:
REQUIREMENTS:
DO NOT:
TEST:

WORKFLOW:
AUDIT → REPRODUCE → IMPLEMENT → TEST → FIX → RETEST → VERIFY → COMMIT → PUSH → REPORT

INTEGRATION:   How this branch should later join the local QA integration branch.
MERGE RISK:    Shared-file or dependency risks.
CONTEXT CONTROL: Smallest relevant file set; expand only when required.
FINAL REPORT:  Branch / worktree / base SHA / tests / conflict risk / merge order.
```

---

## Current parallel model

| Lane | Responsibility | Branch | Class | Notes |
|---|---|---|---|---|
| **A** | Single Device Stabilization | — | CONTROLLED_PARALLEL | May change code |
| **B** | Firebase / Backend / Security Audit | `audit/firebase-security` | SAFE_PARALLEL | Read-only initially |
| **C** | Performance & Firebase Cost Audit | `audit/performance-cost` | SAFE_PARALLEL | Read-only initially |
| **D** | Admin / Privacy / Release Readiness Audit (optional) | `audit/admin-privacy-release` | SAFE_PARALLEL | Read-only initially |

### Serial phase

Once Single Device Stabilization is green, start **Two-Device Core Dating Acceptance**.
During that test no implementation agent may modify:

```
Discovery   Likes   Matching   Compatibility   Chat
E2EE        Typing  Presence   Read receipts   FCM core routing
```

Read-only audits may continue. Defects found during the test get their own isolated branches.

---

## Principle

Parallelize independent investigation and isolated implementation. Do not parallelize
uncontrolled edits to the same subsystem.

The objective is not to maximize running agents — it is to maximize useful parallel progress
while preserving reproducibility, branch isolation, test validity, clean history,
reviewability and safe integration.
