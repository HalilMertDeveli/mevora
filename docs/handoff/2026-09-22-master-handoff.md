# Mevora — Master Handoff

**Date:** 2026-09-22
**Status:** `IN PROGRESS`
**Policy / base SHA:** `6952079857533cfd4a3f407888a856d937c49e7a`

The multi-agent policy is active and [`/CLAUDE.md`](../../CLAUDE.md) is on `origin/main`.
Parallel agent lanes are running. This document is a **status snapshot**, not policy —
`CLAUDE.md` remains the authoritative standard.

> **Written in English to match the repository's other agent-facing docs
> (`CLAUDE.md`, `docs/multi-agent-git-workflow.md`), since agents read them directly.**

---

## Agent status

| Agent | Task | Branch | Commit | Mode | Status |
|---|---|---|---|---|---|
| **A** | Single Device Stabilization | 5 × `fix/*` + `qa/integration-stabilization` | — | IMPLEMENT | **IN PROGRESS** |
| **B** | Firebase / Backend / Security Audit | `audit/firebase-security` | `56063ff` | READ-ONLY | COMPLETED |
| **C** | Performance / Firebase Cost Audit | `audit/performance-cost` | `f4f3a5b` | READ-ONLY | COMPLETED |
| **D** | Admin / Privacy / Release Audit | `audit/admin-privacy-release` | `b5ca61c` | READ-ONLY | COMPLETED |

None of the three audit branches is pushed. No audit modified product code.

---

## Agent A — Single Device Stabilization

Driven by a **separate active agent**. Do not create a duplicate Agent A, and do not touch
its branches, its worktrees under `.tmp/worktrees/`, or its integration branch.

Active work areas:

```
fix/discovery-unmounted-context            fix/data-export-delivery
fix/localization-runtime-errors            fix/account-deletion-verification-runner
fix/photo-picker-multi-select
qa/integration-stabilization               (integration branch — 10 fix branches merged)
```

**Expected final gate:** `READY FOR TWO-DEVICE PHASE: YES`.
Two-Device Core Dating Acceptance must not start before that signal.

### Corrections to the previous handoff draft

Two statements in the earlier draft were stale and are corrected here, because leaving them
in would cause the next agent to redo finished work — the exact failure the
*Do not reimplement* section exists to prevent:

| Earlier draft said | Verified reality (2026-09-22) |
|---|---|
| Photo Picker multi-select — "no branch yet, still in Agent A scope" | **Done.** `fix/photo-picker-multi-select` @ `878f539` exists on `origin` and is already merged into the integration branch (`d0ae6f2`). |
| Integration branch is `qa/stabilization-integration` | **`qa/integration-stabilization`.** Agent A renamed it twice (`qa/device-pass-integration` → `qa/stabilization-integration` → current). Checking out the old name fails. |

**Still genuinely open in Agent A scope:** startup memory investigation (no branch exists),
and the final `Mevora_Emu_A` regression pass.

---

## Agent B — Security audit findings

`2 CRITICAL · 3 HIGH · 8 MEDIUM · 5 LOW · 2 INFORMATIONAL` — full report on the branch.

**F-01 — Client-controlled photo moderation (CRITICAL).** The client holds authority over the
moderation state inside `profiles/{uid}.photos[]`; `completeOnboarding` trusts that
client-controlled state and can mark photos approved and the profile discoverable.
*Risk:* the photo moderation pipeline can be bypassed entirely.
→ `fix/security-profile-photos-server-authority`

**F-02 — Distance-label authorization / trilateration (CRITICAL).** `getDistanceLabel` returns
a distance for any `otherUid` without an adequate authorization, relationship or block check.
Repeated measurements approximate a user's location.
→ `fix/security-distance-label-authorization`

**F-03 — Profile photo URL revocation (HIGH).** Permanent Storage download tokens plus broad
profile read access mean photos can be scraped, may stay reachable after a block, and
takedown/revocation behaviour may be insufficient.
→ `fix/security-photo-url-revocation`

**F-04 — Report abuse (HIGH).** A single report moves the target's photos to `manual_review`,
which can drop them out of Discovery. No threshold, no review lifecycle, no way back.
Independently confirmed by Agent D.
→ `fix/security-report-threshold`

---

## Agent C — Performance / cost findings

14 findings. **A passing two-device acceptance run does not mean `PERFORMANCE/COST PASS`** —
fresh QA accounts have small history collections, so these problems stay invisible.

**PC-01 — Discovery history read amplification (CRITICAL).** Discovery rebuilds user history on
every call at roughly `O(S + P + M + B + G)`, growing over a user's lifetime. Audit estimates:
~50-swipe user ≈ 65 history reads; ~5,000-swipe user ≈ 7,000; a 100-card session ≈ 56,000.
Candidate-scan pagination does **not** solve this — the scan was bounded, the backward history
reconstruction never was.
→ `perf/discovery-history-reads`

| ID | Sev | Issue |
|---|---|---|
| PC-06 | HIGH | Empty deck: `_escalateUntilCandidatesFound` repeats the expensive discovery/history work several times for one deck |
| PC-03 | HIGH | Music/relationship scoring: redundant re-reads and serial round-trip cost |
| PC-02 | HIGH | Per-candidate `isBlocked()` re-reads blocked state already held in memory |
| PC-07 | HIGH | Very high backend read amplification per chat message — the app's highest-frequency flow |

**Sequencing:** PC-02 / PC-03 / PC-04 edit the same loop and will conflict textually; PC-13
reshapes the query they sit inside and must land after them.

---

## Agent D — Admin / privacy / release findings

10 release blockers / findings.

**Admin / moderation.** Code that *consumes* ban/suspend state exists, but there is no real
admin/moderation workflow that can safely *set* it. Parts of the automation/admin
infrastructure are unused: the `processAutomationTask` wiring is missing, and `requireAdmin`,
`adminReviewQueue` and `auditLogs` are not connected to any active flow. Report records can
stay `open` permanently.

**Privacy — Sumsub.** Applicant lifecycle does not complete a real permanent deletion. Reset or
deactivation is not the same as permanent erasure; identity, selfie and biometric data held by
the external provider need their own retention/deletion handling. Treat as a
production/privacy blocker.
→ `fix/privacy-sumsub-applicant-deletion`

**Retention / cleanup.** Cleanup and retention functions exist, but the runtime
scheduler/runner wiring is missing or unverified. Orphan-data lifecycle after account deletion
needs separate verification.

**Release.** Agent D deliberately did not re-file issues already covered by open PRs. Still
requiring verification: production deployment pipeline, production Privacy/Terms URLs,
production Firebase linkage, App Check in production, Sumsub production state.

---

## Cross-audit finding — report abuse

Agents B and D found the same defect independently, which raises confidence considerably.

When one user reports another, the target moves to `profileModerationStatus: manual_review`
and can drop out of Discovery, with no adequate threshold or path back.

**Consequence for QA:** do not run report/block scenarios against the two main A/B test
accounts. Use a separate disposable account/match for destructive report/block testing —
otherwise the main accounts become unusable for the remaining discovery/match tests.

---

## Two-Device Core Dating gate

**Status: `WAITING FOR AGENT A`.**

Audit findings do not fully block the core two-device happy path, but three conditions apply:

1. Do not apply report/block to the main A/B accounts early (see cross-audit finding).
2. If smoke/test credentials are used, clean up or rotate them after the run.
3. A two-device PASS does not clear the performance findings.

When Agent A reports `READY FOR TWO-DEVICE PHASE: YES`, run a synchronization checkpoint
before starting.

---

## Prioritized remediation queue

| # | Branch | Source | Severity |
|---|---|---|---|
| 1 | `fix/security-profile-photos-server-authority` | B F-01 | CRITICAL |
| 2 | `fix/security-distance-label-authorization` | B F-02 | CRITICAL |
| 3 | `fix/security-report-threshold` | B F-04 + D | HIGH / test-impacting |
| 4 | `perf/discovery-history-reads` | C PC-01 | CRITICAL perf/cost |
| 5 | `fix/privacy-sumsub-applicant-deletion` | D | HIGH privacy / external lifecycle |
| 6 | `fix/security-photo-url-revocation` | B F-03 | HIGH |

Task briefs for #1, #2 and #4 are in [`briefs/`](briefs/).

---

## Do not reimplement

Verified sound in the current source. Do not redesign these without new evidence of a defect:

```
match authority                     admin custom-claim gating
unmatch authority                   Sumsub webhook HMAC
compatibility snapshot immutability production IAP fail-closed verification
premium entitlement client          delete-account authorization
  protection                        Firestore/Storage catch-all deny
```

Also settled, despite appearing in older reports: Discovery's **forward candidate scan is
already properly paginated** (pageSize 40, real cursor, batched hydration). Only the backward
history reconstruction is unbounded — that is PC-01, and it is the only part still to fix.

---

## Open questions / decisions

1. **Smoke account security.** The audit found possible smoke-test credential material in
   source. Whether those users actually exist in production Firebase Auth is **unverified** —
   it requires a production read, so it should be a separate security task. That check alone
   decides the finding's real severity.
2. **Android signing.** PR #8 needs separate review: per the audit note, whether the
   debug-sign fallback when no keystore is present is genuinely fail-closed needs
   re-verification.
3. **Agent A.** Outstanding: startup-memory investigation, final Emulator A regression, and
   the `READY FOR TWO-DEVICE PHASE: YES` signal.

---

## Parallel execution

These may start alongside Agent A, each under
`ONE AGENT = ONE TASK = ONE BRANCH = ONE WORKTREE`:

```
fix/security-profile-photos-server-authority
fix/security-distance-label-authorization
perf/discovery-history-reads
```

`fix/security-report-threshold` affects core discovery/moderation behaviour, so integrate it
carefully relative to two-device acceptance.

---

## Runtime state (2026-09-22)

```
emulator-5556   AVD=Mevora_Emu_A   com.mevora.app installed
emulator-5558   AVD=Mevora_Emu_B   com.mevora.app installed
```

Both emulators are live — the two-device setup is ready. Active Firebase project:
`mevora-d6ed0` (development). No Firebase writes or deploys were made while producing the
audits. No temporary deployment exists; no cleanup is required.

`smoke-a@mevora.test` / `smoke-b@mevora.test` — existence in production Auth **unverified**.

No secrets, passwords, tokens or private keys appear in this document or in the audit reports.

---

## User's original worktree

```
Branch    : feature/spotify-music-compatibility
HEAD      : 7beed91e6f358d95aa9bc462a4f66d2b32a4cc39
State     : 5 modified, 14 untracked
UNCHANGED : YES
```

Never stash, reset, clean, commit or switch branches in it.

---

## Next coordinator actions

1. Let Agent A finish its stabilization work.
2. Split the security and performance findings into separate implementation sessions.
3. Prioritize the CRITICAL security branches.
4. Run a synchronization checkpoint once Agent A reports ready.
5. Apply the core subsystem freeze if appropriate.
6. Start Two-Device Core Dating Acceptance on `Mevora_Emu_A` + `Mevora_Emu_B`.
7. Keep destructive report/block tests off the main A/B accounts.
