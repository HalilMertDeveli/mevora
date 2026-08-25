# MEVORA GIT HANDOFF

**Date:** 2026-08-25  
**Remote:** `origin` → `https://github.com/HalilMertDeveli/mevora.git`

## Stable Baseline

- **Commit:** `dd03fd1` — `feat: harden privacy, security rules, and fail-closed E2EE`
- **Tag:** `qa-stable-baseline`
- **Branch:** `qa/baseline`
- **Prior working branch:** `backup/wip-before-device-sync-20260824` (tip still at baseline)

## QA Branches

| Branch | Purpose |
|--------|---------|
| `qa/baseline` | Immutable pointer to stable baseline |
| `qa/firebase` | Emulator multi-user seed/verify + ADB helper |
| `qa/release` | Full QA markdown reports + readiness (RED) |
| `qa/integration` | Aggregated successful QA checkpoints |

## Fix Branches

| Branch | Status |
|--------|--------|
| `fix/fcm-incoming-like-types` | **Successful** — Functions `incomingLike` compile fix |

## Successful Fixes

1. **FCM incomingLike types** (`b9692f3` on `fix/fcm-incoming-like-types`)  
   - Also merged into `qa/integration`

## Failed Attempts

- None as dedicated fix branches.  
- Integration_test multi-emu email auth **hung** (process killed); no bad fix commit created. Next attempt should be `fix/integration-email-auth-v1` (or continue from `test/qa-suite-alignment`).

## Stable Checkpoints (tags)

| Tag | Meaning |
|-----|---------|
| `qa-stable-baseline` | Pre-workflow stable product tip |
| `qa-stable-fcm-fix` | FCM fix checkpoint |
| `qa-stable-reports` | Documentation/report checkpoint |

## Release Branch

- `release/mevora-v1.0.0-rc1` → same commit as `qa/integration`
- **Not ready for production.** RC tracks QA aggregation only.
- **No `v1.0.0` production tag created** (release readiness RED).

## Release Tag

- **None for production.**  
- Use QA tags above until dual-device UI E2E + signing are green.

## Current Working Tree

- Primary handoff branch: `qa/integration`
- Untracked local-only: `.codex/` (not committed)
- Dirty user WIP fully snapshotted on `wip/preserve-dirty-tree-20260825` including:
  - automation admin (`functions/src/automation/`, hosting admin)
  - App Check bootstrap fallback token change
  - `firebase_remote_config` datasource
  - pubspec Remote Config bump
  - production go-live docs

## Uncommitted Changes

- Expect only local IDE/config leftovers such as `.codex/` after this workflow.
- Do **not** delete preserve branch; it is the safety net for non-QA WIP.

## Recommended Next Development Branch

Start from:

```text
qa/integration
```

Then for the next concrete bug:

```text
fix/<short-description>
```

Examples:

- `fix/auth-semantics-keys` — make ADB/integration email login reliable  
- `fix/integration-email-auth-v1` — stabilize multi_user_email_auth_test  
- `chore/play-signing` — replace debug release signing  

Do **not** develop directly on `main`.  
Do **not** treat `release/mevora-v1.0.0-rc1` as shippable until readiness flips from RED.

## How to recover

| Goal | Command |
|------|---------|
| Return to pre-QA product tip | `git checkout qa-stable-baseline` or `qa/baseline` |
| Continue aggregated QA work | `git checkout qa/integration` |
| Recover full dirty WIP | `git checkout wip/preserve-dirty-tree-20260825` |
| Inspect FCM-only fix | `git checkout fix/fcm-incoming-like-types` |

## Push expectation

All of the above branches and `qa-*` tags should be on `origin` after this workflow push.
