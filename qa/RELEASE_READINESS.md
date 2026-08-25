# Mevora Release Readiness

**Date:** 2026-08-25  
**Branch:** `backup/wip-before-device-sync-20260824`  
**Evaluated as:** Google Play / App Store candidate tomorrow morning  

---

## MEVORA RELEASE READINESS

# 🔴 NOT READY FOR RELEASE

---

## Why not ready (objective blockers)

1. **No physical device E2E this run** — camera, mic, FCM kill-state, real keyboard, Play Integrity, permission deny UX unverified.  
2. **Dual-user live messaging (text/image/voice) not proven** — store-critical path.  
3. **Release still signed with debug keys** — Play upload impossible as currently configured.  
4. **R8/minify off** — store hardening incomplete.  
5. **Hardened Firestore/Storage rules + Functions not deploy-smoked** against the live target in this session (client fail-closed E2EE may break chat if backend lagging).  
6. **Full happy-path** signup → onboarding → discover → match → chat → logout → delete **not completed live**.  
7. **iOS archive / Apple Sign-In** not available on this Windows host.  

## What is in good shape

- Large automated suite green (**654** Flutter + **78** Functions) after QA fixes  
- Debug + **release** APKs build; release cold-starts to auth UI on emulator  
- Auth gate UI complete (5 providers + legal)  
- Privacy/security E2EE harden commit present (`dd03fd1`) + notifications compile fix  
- Integration launch smoke green (development)  

## Gate checklist for flipping to yellow/green

| Gate | Status |
|------|--------|
| Real device dual-user chat+voice+image | OPEN |
| Play upload signing + Internal testing track | OPEN |
| Deploy rules/functions + smoke | OPEN |
| Account delete on smoke users only | OPEN |
| Crash-free 30–60 min soak | OPEN |
| iOS TestFlight path (if shipping Apple) | OPEN |

## Recommended morning actions (priority)

1. Plug in 2 Android phones; identical APK + App Check debug token; run USER A/B chat+voice+image matrix.  
2. Create Play App Signing / upload keystore; wire release `signingConfig`; enable minify carefully.  
3. Deploy functions + firestore/storage rules to `mevora-d6ed0` (or prod target); run `prepareSmokeTestUsers` then full funnel; cleanup.  
4. Commit QA fixes (notifications + tests + integration smoke) if not already.  
5. Do **not** ship until dual-user messaging and delete-account smoke are green.  

## Status options (chosen)

- ~~🟢 READY FOR RELEASE~~  
- ~~🟡 READY WITH KNOWN NON-CRITICAL ISSUES~~  
- **🔴 NOT READY FOR RELEASE** ← selected  
