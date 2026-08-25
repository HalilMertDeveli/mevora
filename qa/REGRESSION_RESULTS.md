# Regression Results (post-fix)

## Flutter unit/widget suite

| Run | Result |
|-----|--------|
| Full `flutter test` after fixes | **654/654 PASS** |
| Targeted: account settings, chat voice rules, profile answers | PASS |
| `integration_test/smoke/app_launch_test.dart` (emulator, development) | **PASS** (after smoke fix) |

## Cloud Functions

| Run | Result |
|-----|--------|
| `npm test` (via `cmd /c`) | **78/78 PASS** |

## Builds

| Artifact | Result |
|----------|--------|
| Debug APK `app-development-debug.apk` | PASS |
| Release APK `app-development-release.apk` | PASS (after registrant regen) |
| Release cold start on emulator | Auth welcome UI rendered; no Flutter FATAL in sampled logcat |

## Feature regressions checked after C1/C2/H1/H2

| Area | Method | Result |
|------|--------|--------|
| Notifications types compile | Functions tests | PASS |
| Account delete UI widget | Widget test | PASS |
| Voice rules vs E2EE storage | Unit test | PASS |
| App launch / Firebase init (dev) | Integration smoke | PASS |
| Auth gate UI | Emulator screenshots (debug + release) | PASS |
| Privacy Policy from auth footer | Emulator screenshot | PASS |

## Not re-verified live (still gated)

- Dual-user realtime chat / image / voice  
- Mutual match creation on live Firebase  
- Account deletion end-to-end on smoke users  
- FCM foreground/background/killed  
- Physical device permission deny matrix  
- 30–60 min performance soak  

## Verdict on regressions of applied fixes

**No regressions detected in automated suites or cold-start release/debug smoke for the fixed defects.**  
Live product E2E remains incomplete — see `RELEASE_READINESS.md`.  
