# Emulator vs Real Device

**QA date:** 2026-08-25  
**Emulator:** `emulator-5554` — sdk gphone16k x86_64, Android API 37  
**Physical:** **NOT CONNECTED** this session (`adb devices` → emulator only)

## This-session matrix

| Feature | Emulator | Real device |
|---------|----------|-------------|
| Install debug APK | PASS | BLOCKED |
| Install release APK | PASS | BLOCKED |
| Cold start → auth welcome | PASS (debug+release) | BLOCKED |
| Auth button presence (Google/Apple/Phone/Spotify/Email) | PASS (screenshot) | BLOCKED |
| Privacy Policy from legal footer | PASS | BLOCKED |
| Integration launch smoke | PASS (after fix) | BLOCKED |
| Google Sign-In complete | NOT TESTABLE (Play Services noise) | BLOCKED |
| Apple Sign-In | N/A on Android emu | BLOCKED / iOS N/A |
| Phone SMS | NOT TESTABLE live | BLOCKED |
| Camera / Gallery | LIMITED | BLOCKED |
| Microphone / voice message | LIMITED | BLOCKED |
| Push notifications (kill state) | NOT TESTABLE | BLOCKED |
| Keyboard / IME | PARTIAL | BLOCKED |
| Location permission deny/allow | PARTIAL (grant via adb possible) | BLOCKED |

## Historical evidence (prior sessions on this machine)

Earlier agent sessions on branch worktree had physical **SM M225FV (`R68T305S3VM`)** connected and documented:

- Same `applicationId` on emulator vs phone can overwrite installs  
- Permission grants differed (emu granted; device often denied) — caused behavioral divergence  
- App Check / SHA / dart-define mismatches caused device splash hangs historically  
- Parity installs with identical APK hash were used for login screenshots  

**Those findings are NOT re-confirmed in this overnight QA window** because the phone is absent. Treat as **historical HIGH risk**, not current PASS.

## Decision rule used

If a feature cannot be proven on a physical device in *this* run → **BLOCKED**, never PASS.  
Emulator PASS does **not** clear hardware-dependent features.  
