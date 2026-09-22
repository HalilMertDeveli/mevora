# Mevora — Multi-Agent Development Policy

**This file is the authoritative multi-agent policy for the Mevora repository.**
It applies to every development, bug-fix, audit, test, performance, security, release and
maintenance task here, and it binds every AI agent working on this repository.

Mevora may be worked on by multiple agents simultaneously. Parallel execution is allowed
**only** when each agent is properly isolated.

> Supersedes `docs/multi-agent-git-workflow.md`. Where the two disagree, this file wins.

---

## Core rule

**ONE AGENT = ONE TASK = ONE BRANCH = ONE WORKTREE**

- Never let two active agents modify files in the same worktree.
- Never continue development directly inside another agent's branch.

Every meaningful independent task gets a dedicated agent, scope, semantic branch, Git
worktree, tests, commit/push, and an independent PR-ready result.

---

## Canonical conventions

### Branch naming — semantic prefixes

There is **no mandatory generic `agent/*` prefix**. Name the branch after the work:

```
fix/*   feat/*   audit/*   perf/*   chore/*   docs/*   test/*
```

```
fix/photo-picker-multi-select      perf/discovery-read-cost
audit/firebase-security            feat/premium-entitlement
chore/multi-agent-policy
```

Lowercase ASCII, hyphen-separated, describes the **task** — not the agent session id.

### Worktree location

All **new** agent worktrees live under one root:

```
D:\Mevora-worktrees\<task-name>
```

```
D:\Mevora-worktrees\single-device-stabilization
D:\Mevora-worktrees\firebase-security
D:\Mevora-worktrees\performance-cost
D:\Mevora-worktrees\premium-entitlement
```

Do not introduce another worktree naming scheme. Existing worktrees under other layouts
(`D:\Mevora-agents\`, `D:\Mevora-<name>`, `.tmp\worktrees\`) are **grandfathered** — leave
them alone; cleanup is a separate future chore.

### Base branch

Default base for independent tasks is **`origin/main`**, verified after `git fetch origin`.
Never silently branch from whichever branch happens to be checked out. A task may base on
another unmerged branch only when it genuinely depends on it, and that dependency must be
documented explicitly (`DEPENDENCY BRANCH:` + `BASE SHA:`).

---

## Worktree isolation

Before any modification:

1. `git fetch origin` and record the exact base SHA.
2. Inspect the user's current worktree.
3. **Do not modify the user's worktree.**
4. Create a separate worktree for this task under `D:\Mevora-worktrees\`.
5. Create or check out only the assigned branch inside it.

### The user's worktree is untouchable

If it is dirty, do **not** stash, reset, clean, check out over, commit, remove untracked
files from, or change the branch of it. Record its state before starting and verify it
unchanged at the end:

```
USER WORKTREE:
branch:
HEAD:
modified files:
untracked files:
```

### Pre-flight report

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
| **SAFE_PARALLEL** | Mostly independent or read-only work | security / performance / admin / release audits |
| **CONTROLLED_PARALLEL** | Implementation that may run simultaneously **only** with clear file ownership | localization fixes, notification routing, data export, photo handling, premium infrastructure |
| **SERIAL_REQUIRED** | Runtime acceptance work where parallel edits would invalidate testing | Two-Device Core Dating Acceptance, final production acceptance, matching/chat/E2EE acceptance while those systems are being modified |

---

## File ownership

Every implementation prompt declares:

```
PRIMARY OWNERSHIP:   - <folder/file>
SHARED FILES:        - <central file>
DO NOT TOUCH:        - <unrelated area>
```

Start inside PRIMARY OWNERSHIP; expand only when a real dependency requires it.

### Shared / high-conflict files

```
pubspec.yaml                    functions/src/index.ts
pubspec.lock                    app_router.dart
firestore.rules                 bootstrap.dart
storage.rules                   shared DI/bootstrap files
firebase.json                   localization ARB files
android/app/build.gradle.kts    GitHub Actions workflows
AndroidManifest.xml
```

When a task needs one: keep the diff minimal, do not reformat unrelated content, evaluate
overlap with active agents, report it explicitly as a shared-file change, and include the
conflict risk in the final report. No cleanup or refactor in shared files unless required.

---

## Dependencies

```
BLOCKED BY:                     <task or NONE>
BLOCKS:                         <task or NONE>
CAN RUN IN PARALLEL WITH:       <tasks>
MUST NOT RUN IN PARALLEL WITH:  <tasks>
```

### Stale base protection

Run `git fetch origin` before implementation and again before the final push. If `main`
moved, do **not** auto-rebase or auto-merge — judge whether the new commits affect this
task and report:

```
BASE STATUS: CURRENT | STALE-BUT-SAFE | REBASE-RECOMMENDED | CONFLICT-RISK
```

Never force rebase. Never force push.

---

## Workflows by agent type

**Audit agents — read-only first** (`audit/firebase-security`, `audit/performance-cost`,
`audit/admin-moderation`, `audit/privacy-gdpr`):

```
AUDIT → VERIFY → CLASSIFY → PRIORITIZE → REPORT
```

Do not let an audit agent turn 15 findings into one giant implementation branch. Each
confirmed defect becomes its own appropriately scoped branch (`fix/security-chat-access`,
`perf/discovery-read-cost`, `fix/privacy-data-export`).

**Implementation agents — one logical change per agent:**

```
AUDIT → REPRODUCE → IMPLEMENT → TARGETED TEST → FIX → RETEST
→ FULL RELEVANT TEST → VERIFY DIFF → COMMIT → PUSH → REPORT
```

**Test / acceptance agents** test a stable integration snapshot. While one runs, no other
agent may modify the subsystem under test. Read-only audits may continue.

---

## QA integration branch

When several independent fixes need combined runtime testing, use a temporary local
integration branch, e.g. `qa/integration-<date-or-phase>`.

- For combined acceptance testing only — never the permanent source of changes
- Individual task branches remain the source of truth
- Do not merge it into `main`; do not push it unless explicitly necessary

Use it for `flutter analyze`, `flutter test`, Functions tests, Firebase rules tests,
builds and emulator acceptance.

---

## Active test freeze

During **Two-Device Core Dating Acceptance**, unrelated implementation agents must not modify:

```
Discovery   Likes   Matching   Compatibility   Chat
E2EE        Typing  Presence   Read receipts   FCM core routing
```

Read-only audits may continue. Defects found during the test get their own isolated branches.

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

---

## Required prompt metadata

Every meaningful Mevora engineering prompt defines:

```
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
```

Implementation prompts then continue with the standard Mevora structure:

```
GOAL → SCOPE → CURRENT BEHAVIOR → EXPECTED BEHAVIOR → REQUIREMENTS → DO NOT → TEST
→ WORKFLOW → INTEGRATION → MERGE RISK → CONTEXT CONTROL → FINAL REPORT
```

---

## Principle

Parallelize independent investigation and isolated implementation. Do not parallelize
uncontrolled edits to the same subsystem.

The objective is not to maximize running agents — it is to maximize useful parallel progress
while preserving reproducibility, branch isolation, test validity, clean history,
reviewability and safe integration.
