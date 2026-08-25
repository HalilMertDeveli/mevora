# Admin Panel & Operations

**Status:** In progress — **not** a completed production admin product on `main` / `qa/integration`.

## What exists today (verified)

| Layer | Evidence | Status |
| --- | --- | --- |
| Firestore `isAdmin()` helper | `firebase/firestore.rules` | Implemented |
| Admin-readable ops collections | `auditLogs`, `automationJobs`, `adminReviewQueue`, reports (admin read) | Rules present |
| Mobile dating app admin UI | — | **Not embedded** in Flutter client |
| Hosting `/admin` + Functions automation package | Branch `wip/preserve-dirty-tree-20260825` (`hosting/public/admin/`, `functions/src/automation/`, `docs/AUTOMATION_ADMIN.md`) | **WIP** |

## Intended direction (WIP / planned)

The preserve-branch design targets a **separate** admin surface from the consumer app:

```text
Dating clients (Flutter)
        ↓
Firebase Auth / Firestore / Storage / Functions
        ↓
Admin Hosting console  (+  Cloud Tasks / schedules)
```

Planned capability areas (only mark Implemented when merged and verified):

| Area | Status |
| --- | --- |
| Dashboard / system health | Planned / WIP |
| User lookup | Planned / WIP |
| Reports queue | Rules + review queue scaffolding; console WIP |
| Blocks visibility | Partial (app + server already enforce blocks) |
| Photo `manual_review` ops UI | Planned |
| Privacy / deletion verification jobs | WIP on preserve branch |
| Audit logging | Rules + WIP automation |
| Roles: SUPER_ADMIN / MODERATOR / SUPPORT / ANALYST | Planned / partial WIP — do not claim production RBAC |

## Safety notes

- Never grant admin claims from the mobile client.
- Admin tooling must not decrypt E2EE chat ciphertext.
- Keep automation dry-runs default for destructive Storage cleanup jobs until reviewed.

## Related docs

- Preserve-branch inventory: `docs/AUTOMATION_ADMIN.md` (on `wip/preserve-dirty-tree-20260825`)
- Security rules: `firebase/firestore.rules`
- Git handoff: `qa/GIT_HANDOFF.md`
