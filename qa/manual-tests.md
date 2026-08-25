# Manual / ADB Tests

## Devices

- emulator-5556 (USER A)
- emulator-5558 (USER B)
- emulator-5554 (live/release; later killed)

## Results

| Test | Result | Notes |
|------|--------|-------|
| Install APK ×3 | PASS | Same commit artifacts |
| Launch MainActivity | PASS | |
| Auth welcome 5 providers | PASS | Screenshots |
| Release cold start | PASS | `release-cold.png` |
| Privacy/legal reachable (prior QA) | PASS | |
| Permission revoke (loc/cam/mic) + relaunch | PASS | No FATAL; welcome still shown |
| Permission re-grant | PASS | |
| ADB email login automation | FAIL | Flutter semantics sparse; taps exited app |
| Network airplane matrix | NOT TESTABLE | Not executed systematically |
| 30+ min soak | NOT RUN | |
| Camera/gallery/mic hardware | LIMITED / NOT TESTABLE | Emulator only |
| Real device | BLOCKED | |

## Screenshots directory

`build/qa-parity/multi-emu/` — welcome, release, permission, multi-serial boots.
