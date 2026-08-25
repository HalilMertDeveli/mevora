# Bugs — Flutter CLI Multi-Emulator QA

## CRITICAL

### C1 — Integration tests hang / fail under multi-emulator load
- **Feature:** Device E2E automation  
- **Actual:** `flutter test integration_test/...` hangs after install or errors with `adb: device not found` when emulators are killed mid-run  
- **Impact:** Blocks automated dual-device UI proof  
- **Fixed?** NO — mitigated by killing hung process; needs isolation (1 emu) + semantics keys  

## HIGH

### H1 — Flutter UI not reliably automatable via UIAutomator
- **Feature:** ADB multi-emu login  
- **Actual:** `uiautomator dump` frequently missing / empty; coordinate taps dismiss app to launcher  
- **Impact:** Cannot complete unattended email login → discover → chat UI funnel  
- **Fixed?** NO (needs Semantics/ValueKey on auth buttons — deferred to avoid drive-by UI changes mid-release QA)

### H2 — Physical device absent
- **Status:** BLOCKED for camera/mic/FCM/keyboard  

### H3 — No Play upload signing / R8 (carry-forward)
- Release still debug-signed in Gradle  

## MEDIUM

### M1 — Firebase emulators require JAVA_HOME not on default PATH  
- **Fixed operationally** this session by setting Studio JBR  

### M2 — Pixel_10_Pro_XL AVD broken (“device no longer exists”)  
- **Mitigated** by creating Mevora_Emu_A/B  

### M3 — Emulator GMS `SecurityException: Unknown calling package name 'com.google.android.gms'`  
- Noise on Google Sign-In path  

### M4 — Three heavy emulators cause instability  
- Recommend max 2 for Flutter integration runs  

## LOW

### L1 — Analyzer double-quote infos in security tests  

## NOT BUGS

- Backend multi-user seed/verify on emulators: healthy  
- Chat AppBar uses `controller.otherName` (source test PASS)  
