# Mevora QA System

## Goal

Validate Mevora as if preparing a store release: static checks, automated tests, Firebase emulator multi-user flows, multi-emulator UI attempts, and real-device gates when hardware is available.

## Ladder

```text
flutter analyze
    ↓
flutter test  (+ functions npm test, firebase/tests)
    ↓
integration_test/smoke (device or emulator)
    ↓
Firebase Emulator Suite seed/verify (tool/qa_multi_user_*)
    ↓
Multi-emulator installs / screenshots / ADB probes
    ↓
Real device (camera, mic, FCM, Play Integrity)
    ↓
Regression after each fix branch
    ↓
Release APK cold start
    ↓
qa/RELEASE_READINESS.md decision
```

## Commands (verified patterns)

```bash
flutter doctor
flutter analyze
flutter test

cd functions && npm test

flutter test integration_test/smoke/app_launch_test.dart \
  -d <deviceId> --flavor development

# Emulator Suite (requires Java on PATH / JAVA_HOME)
firebase emulators:start --only auth,firestore,storage --project mevora-d6ed0
node tool/qa_multi_user_seed_admin.cjs
node tool/qa_multi_user_verify.cjs
```

## Artifacts

| Path | Contents |
| --- | --- |
| `qa/` | Full reports, bugs, fixes, readiness, Git handoff |
| `integration_test/smoke/` | Device launch + email auth harness |
| `tool/qa_multi_user_*` | Emulator multi-user seed/verify |
| `tools/smoke/` | Live Firebase backend smoke (service account) |
| `docs/SMOKE_TEST.md` | Smoke user + runner documentation |

## Honest limitations (latest overnight run)

- Dual-emulator **UI** email login → chat funnel: **Partial / not green**
- Physical device: often **Blocked** when USB phone absent
- Release readiness: **RED** until dual-device messaging + Play signing land

See `qa/FULL_QA_REPORT.md` and `qa/release-readiness.md`.
