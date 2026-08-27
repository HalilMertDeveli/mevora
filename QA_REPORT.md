# QA_REPORT — Mevora Hour Final Live Validation

**Date:** 2026-08-27 (Europe/Istanbul)  
**Commit under test:** `2ead4eb`  
**Firebase:** `mevora-d6ed0`  
**Final decision:** **NOT PRODUCTION READY**

This session was **validation only** (no algorithm / catalog / architecture changes).

---

## 1. TWO USER E2E — MANUAL REQUIRED

**Not executed** with real Auth users or two devices.

Blocked in this agent environment by:

- No App Check attestation for callable invoke  
- No Application Default Credentials for Admin Auth user creation script  
- No physical/emulator dual-device control

Prior admin/MCP-seeded `qa_hour_user_*` docs were **not** a valid two-user E2E (not Auth, not callables, matching written by admin). Those QA docs were **cleaned up** this session.

**Do not treat as PASS.**

---

## 2. LIVE ISTANBUL `:00` SCHEDULER — PASS

Waited until after Istanbul **13:00** (agent clock: `2026-08-27, 13:11:46` Europe/Istanbul).

### Cloud Logging (`matchingGameHourlyTick`)

| Timestamp (UTC) | Log |
|-----------------|-----|
| `2026-08-27T10:00:31.997Z` | `[HOURLY_GAME] round created 2026082713` |
| `2026-08-27T10:00:32.036Z` | `[HOURLY_GAME] no previous round 2026082712` |

`10:00Z` = **13:00 Europe/Istanbul**. Round id `YYYYMMDDHH` = `2026082713`.

### Firestore

Document `matchingGameRounds/2026082713`:

- `status: OPEN`
- `timezone: Europe/Istanbul`
- `createdAt` / `opensAt` ≈ tick time
- `participantCount: 0` (no live users joined)

**Note:** “no previous round 2026082712” is expected for the first natural tick after deploy (no `2026082712` OPEN/COLLECTING round existed).

---

## 3. ROUND LIFECYCLE — NOT TESTED

Observed live: **OPEN** only (empty pool).

Not observed live:

- COLLECTING / MATCHING / COMPLETED driven by CF with real submissions  
- Late submit rejection after MATCHING/COMPLETED  

Code-review expectation remains: submit rejected when status ∉ `{OPEN, COLLECTING}` — **runtime NOT TESTED**.

---

## 4–5. DISCOVER / MESSAGING — MANUAL REQUIRED

No live Discover swipe/like or messaging session run against this backend.

---

## 6. LEGACY FALLBACK — PASS (unit)

Re-ran:

```text
flutter test test/features/relationship/hourly_matching_game_test.dart
→ +3 (includes not-found → legacy dwell fallback)
```

Forcing live CF outage while clients hit production was **not** done → live fallback **NOT TESTED**.

---

## 7. FIRESTORE CLEANUP — PASS

Deleted only QA-tagged artifacts from prior session:

- `matchingGameRounds/qa_prodready_2026082712`
- `.../participants/qa_hour_user_a`
- `.../participants/qa_hour_user_b`
- `.../matches/qa_hour_user_a_qa_hour_user_b`

Post-cleanup list no longer contains `qa_prodready_*`.  
Left intact: live scheduler round `2026082713` (not QA).

---

## 8. FINAL TABLE

| Item | Status |
|------|--------|
| BUILD | **PASS** |
| FUNCTIONS | **PASS** |
| FIRESTORE | **PASS** |
| SCHEDULER | **PASS** |
| ISTANBUL TIMEZONE | **PASS** |
| TWO USER E2E | **MANUAL REQUIRED** |
| ROUND LIFECYCLE | **NOT TESTED** |
| COMPATIBILITY | **NOT TESTED** (live) |
| DISCOVER | **MANUAL REQUIRED** |
| MATCH | **MANUAL REQUIRED** |
| MESSAGING | **MANUAL REQUIRED** |
| LEGACY FALLBACK | **PASS** (unit) |
| CLEANUP | **PASS** |

---

## 9. Verdict

### NOT PRODUCTION READY

### Real blockers only

1. **Two-user live E2E** (same Istanbul round → identical answers → score 100 → mutual result → chat).  
2. **Full lifecycle** with submitted participants (MATCHING→COMPLETED) + late-submit denial.  
3. **Discover + messaging** smoke on a client build against live hourly backend.

Infrastructure gates (build, 6 functions, Firestore round create, Istanbul `:00` tick) are **proven**. Product acceptance still needs the human dual-device checklist above.
