# Mevora Git Workflow (QA Engineering)

## Baseline

- Tag / branch: `qa-stable-baseline` · `qa/baseline`
- Commit: privacy/security E2EE harden tip used as the QA split point

## Branch naming

| Prefix | Use |
| --- | --- |
| `feature/` | Product features |
| `fix/` | Atomic bug fixes |
| `qa/` | QA area checkpoints |
| `test/` | Test harness work |
| `chore/` | Tooling / docs hygiene |
| `hotfix/` | Urgent production fixes |
| `release/` | Release candidates |
| `wip/` | Temporary preserve / experiment snapshots |

## Flow

```text
baseline
  → fix/<short-name> | test/<name> | qa/<area>
  → tests pass
  → commit (atomic message)
  → push origin
  → merge into qa/integration
  → optional release/<app>-vX.Y.Z-rcN
```

Failed experiments: keep the branch; continue on `fix/<name>-v2` instead of deleting history.

## Safety

- Do not force-push `main`
- Do not `git reset --hard` / `git clean -fd` to discard others' work
- Preserve dirty trees on `wip/*` before splitting commits

## Handoff

Full branch/tag inventory: [qa/GIT_HANDOFF.md](../qa/GIT_HANDOFF.md) · [qa/git-workflow.md](../qa/git-workflow.md)
