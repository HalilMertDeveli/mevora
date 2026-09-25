# Mevora Multi-Agent Git Workflow

> **⚠️ SUPERSEDED — see [`/CLAUDE.md`](../CLAUDE.md) (Mevora Parallel Agent Development Standard).**
>
> That standard is the single source of truth for branch naming, worktree isolation, parallel
> safety classification, file ownership and merge order. Where this document disagrees with it,
> **the standard wins**. Known divergences below: branch prefix (`agent/*` here vs
> `audit/*` `fix/*` `perf/*` in the standard), worktree location (`D:\Mevora-agents\<slug>`
> here vs `../mevora-<task>` in the standard), and base branch (`main` here vs `origin/main`).
>
> Retained for historical context and for the existing `agent/*` worktrees already checked out.

This document defines how multiple Cursor Agents work on Mevora **without overwriting each other**.

## Goals

- Each agent owns **one branch** (and ideally **one worktree**).
- **`main`** is protected: agents do not develop directly on it.
- Uncommitted user work is **never** destroyed (`git reset --hard`, `git clean -fd`, `git checkout -- .` are forbidden unless the user explicitly requests them).
- Conflicts are **reported and stopped**, not silently resolved by deleting another agent's work.

---

## Repository

| Item | Value |
|------|--------|
| Remote | `https://github.com/HalilMertDeveli/mevora.git` |
| Primary clone | `D:\Mevora` |
| Standard agent worktrees | `D:\Mevora-agents\<task-slug>\` |
| Legacy / feature worktrees | See [Existing worktrees](#existing-worktrees) |

---

## Branch naming

```
agent/<short-task-name>
```

Examples:

- `agent/responsive-ui`
- `agent/device-compatibility`
- `agent/qa`
- `agent/firebase`
- `agent/chat`
- `agent/auth`
- `agent/performance`

Rules:

- Lowercase ASCII only
- No spaces, no Turkish characters
- Use hyphens for words
- Name must describe the **task**, not the agent session id

Feature branches outside the `agent/` prefix (e.g. `feature/humor-lab-mvp`, `qa/production-readiness`) remain valid for long-running product work; new parallel agent tasks should prefer `agent/*`.

---

## Worktree strategy

**Branch-only isolation is not enough** when several agents share `D:\Mevora`. Git allows one checked-out branch per worktree; two agents editing the same folder will corrupt each other's working trees.

### Preferred model

```text
D:\Mevora                          → shared / integration / current feature (avoid multi-agent edits)
D:\Mevora-agents\
    responsive-ui\                 → agent/responsive-ui
    device-compatibility\          → agent/device-compatibility
    qa\                              → agent/qa
    firebase\                        → agent/firebase
    chat\                            → agent/chat
    auth\                            → agent/auth
    performance\                     → agent/performance
```

### Create a new agent worktree (from updated main)

```powershell
cd D:\Mevora
git fetch origin main
git worktree add -b agent/<task-name> D:\Mevora-agents\<task-slug> origin/main
```

Open **`D:\Mevora-agents\<task-slug>`** in Cursor (not `D:\Mevora`) before implementing.

### Remove a finished worktree (after merge / handoff)

```powershell
cd D:\Mevora
git worktree remove D:\Mevora-agents\<task-slug>
git branch -d agent/<task-name>   # only after merged
```

---

## Agent startup checklist (mandatory)

Before changing any file:

```powershell
git status
git branch --show-current
git worktree list
```

Record:

```text
Agent role:        <e.g. Responsive UI Agent>
Repository path:   <absolute path>
Current branch:    <branch>
Expected branch:   agent/<task-name>
Working tree:      clean | dirty (list files)
Status:            OK | STOP
```

**If `Current branch` ≠ `Expected branch` → STOP. Do not edit files.**

**If repository path is `D:\Mevora` but another agent owns that feature → STOP. Switch to your worktree.**

**If `git status` is dirty and you did not create those changes → STOP and report. Do not stash automatically.**

---

## Agent workflow

```text
AUDIT → IMPLEMENT → TEST → FIX → RETEST → VERIFY → REPORT → COMMIT
```

All steps happen on **your** branch/worktree only.

### Commit messages

Use conventional commits scoped to the task:

```text
feat(responsive): improve discover card constraints
fix(chat): make image bubbles responsive
test(device): add small-screen layout coverage
```

Prefer several focused commits over one giant commit.

---

## Main branch protection

- Agents **must not** implement features on `main`.
- Agents **must not** merge into `main` without explicit user approval.
- Agents **must not** force-push `main`.

`main` is for stable integration, release, and production promotion only.

---

## Cross-agent rules

| Rule | Action |
|------|--------|
| Working on another agent's branch | **Forbidden** |
| Reverting another agent's commits | **Forbidden** |
| Editing files in another agent's worktree | **Forbidden** |
| Auto-stashing unknown dirty state | **Forbidden** — report first |
| `git reset --hard` / `git clean -fd` | **Forbidden** unless user explicitly asks |

---

## Merge policy

Normal flow:

```text
Agent → own branch → tests → commit → report → human review → merge → main
```

Before merge (human or release agent):

```powershell
flutter analyze
flutter test
# plus functions build/tests if backend touched
```

Agents do **not** merge to `main` autonomously.

---

## Conflict handling

If two branches touch the same file:

```text
CONFLICT DETECTED

File: lib/features/discovery/presentation/pages/discovery_page.dart
Agent A branch: agent/responsive-ui
Agent B branch: agent/qa

Action: STOP AND REPORT
```

Do not pick one side and delete the other. Coordinate via report + user review.

---

## Shared / high-risk files

Multiple agents often collide on:

| Area | Paths (examples) |
|------|------------------|
| Dependencies | `pubspec.yaml`, `pubspec.lock` |
| Firebase | `firebase/`, `lib/firebase_options.dart`, `google-services.json`, `GoogleService-Info.plist` |
| Native | `android/`, `ios/`, Gradle, Podfile, manifests |
| Routing / shell | `lib/core/routing/`, `lib/bootstrap.dart`, `lib/main*.dart` |
| DI / config | `lib/core/di/`, `lib/core/config/` |
| Theme / layout | `lib/core/theme/`, `lib/core/constants/` |
| Functions entry | `functions/src/index.ts` |

**Policy:** Only one active agent should modify a shared file per integration cycle. If you must touch a shared file, state it in your handoff report.

---

## Handoff report template

```text
Branch:     agent/responsive-ui
Worktree:   D:\Mevora-agents\responsive-ui
Commits:    abc1234, def5678

Changed:
- lib/features/discovery/...

Tests:
- flutter analyze → PASS
- flutter test → PASS (N tests)

Status: READY FOR REVIEW
```

---

## Existing worktrees (legacy)

These predate the `D:\Mevora-agents` layout. **Do not delete** unless the user asks. Prefer new tasks in `D:\Mevora-agents\`.

| Path | Branch | Notes |
|------|--------|-------|
| `D:\Mevora` | varies | Shared checkout — **single agent at a time** |
| `D:\Mevora-qa` | `qa/production-readiness` | QA / production readiness |
| `D:\Mevora-full-qa` | `qa/full-project-stabilization` | Full QA cycle |
| `D:\Mevora-humor-ship` | `feature/humor-lab-ship` | Humor Lab ship |
| `D:\Mevora-phase3-recovery` | `feature/humor-lab-mvp` | Humor recovery |
| `D:\Mevora-worktrees\compatibility-reveal` | `feature/compatibility-reveal` | Compatibility Reveal |
| `D:\Mevora-spotify-agent` | `feature/agent-spotify-music-compatibility` | Spotify agent |
| … | … | Run `git worktree list` from `D:\Mevora` for full list |

Detached HEAD worktrees (`D:\Mevora-faz42-clean`, `D:\Mevora-matching-streak`) should be repaired or removed in a dedicated cleanup — agents must not commit from detached HEAD.

---

## Cursor integration

Project rule: `.cursor/rules/multi-agent-git-isolation.mdc` (`alwaysApply: true`).

Every Cursor Agent session should read and follow that rule before editing files.

---

## Quick reference commands

```powershell
# List everything
git worktree list
git branch -a
git status

# Start new agent task
git fetch origin main
git worktree add -b agent/my-task D:\Mevora-agents\my-task origin/main

# Verify before commit
git status
git diff --stat
flutter analyze
flutter test
```
