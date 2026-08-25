# E2E Report

## Intended funnel

```text
A signup → onboarding → profile → questions
B signup → onboarding → profile → questions
A like B → B like A → MATCH
A chat → B receive → B reply → A receive
```

## What actually ran end-to-end

### Layer 1 — Firebase Emulator backend E2E (PASS)

| Step | Method | Result |
|------|--------|--------|
| Create USER A/B/C | Auth Emulator + Admin | PASS |
| Seed profiles/prefs/location/answers | Admin Firestore | PASS |
| Mutual like + match | Admin Firestore | PASS |
| Text message A→B | Admin Firestore | PASS |
| Change B answer q3 | Admin Firestore | PASS |
| Verify read-back consistency | `qa_multi_user_verify.cjs` | **PASS 14/14** |
| Valid/invalid password login | Auth REST | PASS |

This proves multi-user data model + match/message/answer-change persistence on the emulator backend.

### Layer 2 — App process E2E on emulators (PARTIAL)

| Step | Result |
|------|--------|
| Install same emu-mode APK on A & B | PASS |
| Cold start → auth gate | PASS (screenshots) |
| Email form navigation via ADB | FAIL/UNRELIABLE |
| UI login as qa-a / qa-b | NOT COMPLETED |
| Discover swipe UI | NOT TESTABLE (no auth session in UI) |
| Chat UI dual-device | NOT TESTABLE |
| Image/voice UI | NOT TESTABLE |

### Layer 3 — Live Firebase device E2E

NOT RUN against production/live for multi-user (no service account; avoid production data mutation). Live debug/release cold start to auth UI on emulator: PASS.

## Feature E2E matrix (honest)

| Feature | Backend emu | App UI multi-emu | Real device |
|---------|-------------|------------------|-------------|
| Auth email accounts | PASS | PARTIAL | BLOCKED |
| Profiles | PASS | BLOCKED | BLOCKED |
| Questions/answers + change | PASS | BLOCKED | BLOCKED |
| Matching / likes | PASS (seeded) | BLOCKED | BLOCKED |
| Chat text | PASS (seeded) | BLOCKED | BLOCKED |
| Image message | NOT TESTABLE | BLOCKED | BLOCKED |
| Voice message | NOT TESTABLE | BLOCKED | BLOCKED |
| Peer display name plumbing | PASS (code + message text) | BLOCKED UI | BLOCKED |
| Account delete | NOT RUN | BLOCKED | BLOCKED |

## Integration_test status

- `app_launch_test.dart`: previously PASS on single emu; under multi-emu + emulator defines: hang/fail.
- `multi_user_email_auth_test.dart`: added; hung after APK install (killed). Needs stable single-device run + semantics keys.

## Conclusion

**Backend multi-user E2E on Firebase Emulator Suite is green.**  
**Full UI multi-emulator user journey is not green** — release cannot claim dual-device chat proven in-app.
