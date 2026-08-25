# Manual / Emulator Test Results

**Environment:** Android emulator `emulator-5554` only  
**Firebase project (dev):** `mevora-d6ed0`  
**Physical device:** BLOCKED  

Legend: PASS / FAIL / BLOCKED / NOT TESTABLE / PARTIAL

## Auth

| Scenario | Result | Evidence |
|----------|--------|----------|
| Cold start shows auth welcome | PASS | `build/qa-parity/release-boot.png`, `manual2/debug-token-boot.png` |
| Google / Apple / Phone / Spotify / Email buttons visible | PASS | Screenshots |
| Email valid login | BLOCKED | No unattended credentials used; smoke users secret-gated |
| Email invalid / empty | PARTIAL | UIAutomator unreliable; coordinate taps hit legal pages |
| Phone SMS valid/invalid/resend | NOT TESTABLE | Needs carrier/SMS or Console test pair + manual |
| Google Sign-In complete | NOT TESTABLE | Emulator Play Services errors observed |
| Apple Sign-In | NOT TESTABLE | Android emu |
| Spotify OAuth complete | NOT TESTABLE | Needs interactive OAuth |
| Logout / relogin / session restore | PARTIAL | Earlier session showed persisted Settings login; reinstall cleared session |
| App restart after auth | PARTIAL | Release/debug cold starts to auth when logged out |

## Onboarding (new account)

| Scenario | Result |
|----------|--------|
| Full new-user onboarding | BLOCKED / NOT TESTABLE unattended |
| Field validation matrix | NOT TESTABLE live (covered partly by widget tests) |

## Permissions

| Scenario | Result |
|----------|--------|
| Allow all via `pm grant` | PARTIAL historically |
| Deny / permanent deny UX | NOT TESTABLE this run |

## Profile / Questions / Discover / Matching / Matches

| Scenario | Result |
|----------|--------|
| Profile edit + persistence | NOT TESTABLE live this run |
| Q&A edit sync | Automated unit/widget PASS; live BLOCKED |
| Discover swipe / empty / error | NOT TESTABLE live (no authenticated session driven) |
| Mutual like / score / duplicates | Automated + prior code review; live BLOCKED |

## Chat / Media / Voice / Names

| Scenario | Result |
|----------|--------|
| Text A↔B realtime | BLOCKED (need 2 users/devices) |
| Image upload | BLOCKED |
| Voice record/play | BLOCKED on hardware; unit/rules PASS |
| Hardcoded “Mevora” as peer name | NOT TESTABLE live |

## Settings / Account

| Scenario | Result |
|----------|--------|
| Settings rows visible when logged in | PASS (earlier UI dump: edit profile, password, Spotify, preferences, verify, blocked, privacy, location; email shown) |
| Privacy Policy from auth | PASS |
| Delete account E2E | NOT RUN (would destroy data; smoke callable not invoked) |
| Data export | Widget coverage; live NOT TESTABLE |

## Navigation / Lifecycle / Network / Perf

| Scenario | Result |
|----------|--------|
| Bottom nav walk | FAIL/PARTIAL — taps left app to launcher/Google after bad install state |
| Background/resume | NOT TESTABLE systematically |
| Airplane mode matrix | NOT TESTABLE |
| 30–60 min soak | NOT RUN |

## Crash / Log sample

- Release/debug cold start samples: **no Flutter FATAL / Dart unhandled** in filtered windows  
- Emulator GMS `SecurityException` noise present  

## Important install note

After `integration_test` install, package briefly had **no launcher activity** until APK reinstall — treat as tooling hazard for unattended runs.  
