# Fixes Applied — This Multi-Emulator QA Window

| Item | Change | Why | Verification |
|------|--------|-----|--------------|
| AVD fleet | Created `Mevora_Emu_A`, `Mevora_Emu_B` | Only broken Pixel_10 AVD existed | Both booted on ports 5556/5558 |
| Firebase emulators | Started with `JAVA_HOME` = Android Studio JBR | `java -version` missing from PATH | Auth/Firestore/Storage ready |
| Multi-user seed | `tool/qa_multi_user_seed_admin.cjs` | REST writes blocked by rules | Seed OK |
| Multi-user verify | `tool/qa_multi_user_verify.cjs` | Assert Auth/Firestore consistency | 14/14 PASS |
| Integration scaffold | `integration_test/smoke/multi_user_email_auth_test.dart` | Email auth E2E harness | Hung — needs follow-up |
| Peer name guard | `test/features/chat/chat_peer_name_source_test.dart` | Prevent hardcoded Mevora title regression | 2 PASS |
| ADB login helper | `tool/qa_adb_email_login.ps1` | Attempt UI login | Unreliable (documented) |

## Intentionally not changed

- Matching algorithm, question catalog, production data  
- Auth button Semantics/Keys (would be a UI instrumentation change; deferred)  
- Existing dirty WIP (automation admin, bootstrap, etc.) left intact  
- No `git reset --hard` / force-push  

## Prior QA fixes still in tree (from earlier overnight run)

- Functions `incomingLike` FCM types  
- Account settings / voice rules / profile answers tests  
- Integration smoke development bootstrap  
