# Mevora Git Workflow — QA Engineering

**Generated:** 2026-08-25  
**Remote:** `https://github.com/HalilMertDeveli/mevora.git`  
**Baseline:** `dd03fd1` / tag `qa-stable-baseline`

## Stable Baseline

| Item | Value |
|------|-------|
| Commit | `dd03fd1` |
| Message | feat: harden privacy, security rules, and fail-closed E2EE |
| Branch at discovery | `backup/wip-before-device-sync-20260824` |
| Tag | `qa-stable-baseline` |
| Branch pointer | `qa/baseline` |

This is the last known privacy/E2EE harden point **before** splitting QA git workflow commits. Working tree dirty content was **not** deleted; it was snapshotted first.

## Branch Map

| Branch | Purpose | Base | Result | Remote |
|--------|---------|------|--------|--------|
| `qa/baseline` | Pointer to stable baseline | `dd03fd1` | Stable | push |
| `wip/preserve-dirty-tree-20260825` | Full dirty-tree safety snapshot (automation WIP + QA + App Check bootstrap) | `dd03fd1` | Preserved | push |
| `fix/fcm-incoming-like-types` | Restore missing `incomingLike` FCM types | `dd03fd1` | SUCCESS | push |
| `test/qa-suite-alignment` | Test/integration harness alignment | `dd03fd1` | SUCCESS (unit green) | push |
| `qa/firebase` | Emulator multi-user seed/verify tooling | `dd03fd1` | SUCCESS | push |
| `qa/release` | QA reports + RED readiness docs | `dd03fd1` | SUCCESS (docs) | push |
| `qa/integration` | Merge of successful QA checkpoints | merges above | SUCCESS merge | push |
| `release/mevora-v1.0.0-rc1` | Release-candidate tracking branch (= integration) | `qa/integration` | **RC only — NOT production** | push |
| `main` | Untouched | — | Protected | — |
| `backup/wip-before-device-sync-20260824` | Prior backup branch | — | Unchanged tip `dd03fd1` | already remote |

## Atomic Commits (QA workflow)

| Commit | Branch | Message |
|--------|--------|---------|
| `a1188dc` | `wip/preserve-dirty-tree-20260825` | chore: preserve dirty working tree before QA git workflow |
| `b9692f3` | `fix/fcm-incoming-like-types` | fix: restore missing incomingLike FCM notification types |
| `32b90bf` | `test/qa-suite-alignment` | test: align QA suite with E2EE storage and export UI |
| `348ec7c` | `qa/firebase` | test: add Firebase emulator multi-user seed and verify tooling |
| `dbdd138` | `qa/release` | docs: add full QA and multi-emulator release readiness reports |
| merge commits | `qa/integration` | merge: bring in … |

## Tags / Checkpoints

| Tag | Points to | Meaning |
|-----|-----------|---------|
| `qa-stable-baseline` | `dd03fd1` | Pre-QA-split stable |
| `qa-stable-fcm-fix` | `fix/fcm-incoming-like-types` | Functions compile fix |
| `qa-stable-reports` | `qa/release` | Report checkpoint |

## Intentionally NOT merged to main

- Product release decision is still **RED**
- Automation admin WIP lives only on preserve branch (not cherry-picked into `qa/integration`)
- App Check hardcoded fallback token change stays on preserve branch (not in integration)

## Failed experiment branches

None created yet (UI automation hang was process kill, not a failed fix commit). Future voice/UI fix attempts should use `fix/<name>` then `fix/<name>-v2` without deleting v1.

## Safety rules applied

- No `git reset --hard`
- No `git clean -fd`
- No force push
- No branch `-D`
- No edits to `main`
- `.codex/` left untracked
- Emulator seed passwords redacted in committed `qa/multi_user_seed.json`
