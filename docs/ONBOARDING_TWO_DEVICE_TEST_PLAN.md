# Onboarding two-device manual test plan

Use this checklist on two real phones after installing the development APK
(`Mevora Dev` / `com.mevora.app`). Landscape is supported — do not force portrait.
Validate scroll, keyboard, and Safe Area on every onboarding step.

## Shared flow

```text
New user → Register / phone / Google → Location → Profile wizard
→ Photos → Complete celebration → Start Discovering → Discover
→ Force-quit app → Relaunch → Discover (must NOT reopen onboarding)
```

## Device A

1. Install a clean build (uninstall previous Mevora Dev if needed).
2. Create **User A** (new phone number or Google account).
3. Complete location permission (allow, city, or skip as needed).
4. Finish every onboarding step: basic info, interests, education,
   relationship goal, lifestyle, bio, photos (min 3), complete.
5. Confirm **Discover** opens and is usable.
6. Force-quit the app and reopen.
7. Confirm you land on **Discover** again — not login, not onboarding.
8. Note User A display name and city for cross-check later.

## Device B

1. Install the same APK build.
2. Create **User B** with a **different** account than Device A.
3. Complete onboarding → Discover.
4. Force-quit and relaunch → still Discover.
5. Confirm User B profile does not show User A data (name, photos, city).

## Cross-login

1. On Device B, sign out, then sign in as **User A**.
2. Confirm Discover and profile match Device A’s User A.
3. Confirm onboarding is **not** shown again.

## Failure cases to spot-check

- Airplane mode during “Start Discovering” → error + retry, no silent Discover.
- Kill app on celebration screen before CF → reopen stays on celebration, retry works.
- Slow network → loading disables duplicate taps.

## Pass criteria

| Check | Pass |
| ----- | ---- |
| New user reaches Discover | |
| App restart stays out of onboarding | |
| Second device / second user isolated | |
| Cross-login shows correct profile | |
| Completion error shows retry | |
