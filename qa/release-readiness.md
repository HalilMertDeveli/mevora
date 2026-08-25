# Release Readiness — Flutter CLI Multi-Emulator QA

**Date:** 2026-08-25

## Decision

# 🔴 RED — NOT READY FOR RELEASE

## Feature matrix

FEATURE | AUTOMATED | MANUAL | EMULATOR | REAL DEVICE | RESULT
---|---|---|---|---|---
Authentication (email accounts) | PASS (Auth emu + unit) | PARTIAL | PARTIAL (welcome only) | BLOCKED | **PARTIAL**
Authentication (Google/Apple/Phone/Spotify complete) | PARTIAL | NOT TESTABLE | NOT TESTABLE | BLOCKED | **NOT READY**
Onboarding | PARTIAL (widgets) | BLOCKED | BLOCKED | BLOCKED | **NOT READY**
Profile | PASS (seed/verify) | BLOCKED | BLOCKED | BLOCKED | **PARTIAL**
Questions / Answers | PASS (seed + change) | BLOCKED | BLOCKED | BLOCKED | **PARTIAL**
Discover | PARTIAL (unit) | BLOCKED | BLOCKED | BLOCKED | **NOT READY**
Matching | PASS (seeded match) | BLOCKED | BLOCKED | BLOCKED | **PARTIAL**
Messaging text | PASS (Firestore seed/verify) | BLOCKED | BLOCKED | BLOCKED | **PARTIAL**
Messaging image | NOT TESTABLE | BLOCKED | BLOCKED | BLOCKED | **NOT READY**
Messaging voice | PASS (rules/unit prior) | BLOCKED | BLOCKED | BLOCKED | **NOT READY**
Peer display name | PASS (source + seed text) | BLOCKED | BLOCKED | BLOCKED | **PARTIAL**
Settings / permissions | PARTIAL | PASS (revoke smoke) | PASS | BLOCKED | **PARTIAL**
Account deletion | PARTIAL (unit prior) | NOT RUN | NOT RUN | BLOCKED | **NOT READY**
Release APK cold start | PASS | PASS | PASS | BLOCKED | **PASS**
Multi-emulator UI chat | FAIL | FAIL | FAIL | BLOCKED | **FAIL**

## Why RED

1. Dual-emulator **in-app** login → match → chat not completed.  
2. No physical device verification.  
3. Image/voice UI E2E not proven.  
4. Integration_test harness unstable under multi-emu.  
5. Release signing still debug (store blocker).  

## What is green enough to build on tomorrow

- Flutter **654** + Functions **78** automated green  
- Firebase Emulator multi-user Auth/Firestore seed+verify **PASS**  
- 2 custom AVDs + tooling scripts ready for next UI automation pass  
- Release APK installs and shows auth UI  

## Morning next steps

1. Add Semantics/ValueKey on auth email/sign-in buttons; re-run ADB + integration_test on **one** emu first, then two.  
2. Plug in 2 phones; live Firebase smoke users (secret-gated) for chat/voice/image.  
3. Wire Play signing + minify.  
4. Deploy hardened rules/functions; smoke.  
5. Do not ship until FEATURE matrix Messaging + Matching show PASS on EMULATOR **and** REAL DEVICE columns.
