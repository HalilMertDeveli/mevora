# Multi-Emulator Report

## Emulator fleet

| Role | Serial / AVD | Mode APK | Status |
|------|--------------|----------|--------|
| USER A | `emulator-5556` / Mevora_Emu_A | Emulator Suite APK | Booted; auth welcome screenshot PASS |
| USER B | `emulator-5558` / Mevora_Emu_B | Emulator Suite APK | Booted; auth welcome screenshot PASS |
| USER C / live | `emulator-5554` (pre-existing) | Live Firebase debug/release | Auth welcome PASS; later killed for load |

## Same-commit install

Identical `app-development-debug-emulators.apk` installed on A + B after building with:

```text
--dart-define=USE_EMULATORS=true
--dart-define=USE_AUTH_EMULATOR=true
--dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2
```

Live release APK installed on 5554 for cold-start parity → PASS.

## Multi-user backend (emulator Firebase)

Seeded via Admin SDK (rules bypass **only** on local emulators):

| User | Email | displayName | Result |
|------|-------|-------------|--------|
| A | qa-a@mevora.test | Test User A | PASS |
| B | qa-b@mevora.test | Test User B | PASS |
| C | qa-c@mevora.test | Test User C | PASS |

Created mutual likes + active match A↔B + text message from A→B.

Verify script (`tool/qa_multi_user_verify.cjs`): **14/14 PASS** including:

- Auth users exist
- Profiles with real display names
- Shared + changed relationship answers (B `q3=CHANGED`)
- Match active
- Message text contains peer name (not brand-only)
- Sender is A

Auth password login via Auth Emulator REST: A/B/C LOGIN_OK; invalid password rejected.

## UI multi-emulator interaction

| Step | Result |
|------|--------|
| Launch A+B+C | PASS |
| Auth welcome visible on A + live C | PASS |
| ADB semantics dump for Flutter buttons | FAIL (uiautomator often empty / not idle) |
| Coordinate taps for email | UNRELIABLE (often bounced to launcher) |
| Full UI signup→chat on two devices | **BLOCKED / PARTIAL** |

## Resource pressure

Running 3× API 37 Play emulators + Gradle + Firebase emulators caused:

- Slow/hung `flutter test integration_test`
- Occasional black/tiny screenshots on B after reinstall
- `adb: device not found` races when killing 5554 mid-flutter-test

## Real device

**BLOCKED** — not connected.
