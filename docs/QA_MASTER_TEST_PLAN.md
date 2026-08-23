# Mevora — QA Master Test Plan

Audit date: 2026-08-23  
Scope: Flutter client + Firebase (Auth, Firestore, Storage, Cloud Functions)  
Method: Static analysis, automated tests, code audit, security rules review. **No code changes during audit.**

---

## 1. Project Build

| ID | Scenario | Method | Priority |
|----|----------|--------|----------|
| MEV-TC-B001 | `flutter doctor` | CLI | P0 |
| MEV-TC-B002 | `flutter pub get` | CLI | P0 |
| MEV-TC-B003 | `flutter analyze` | CLI | P0 |
| MEV-TC-B004 | `flutter test` (full suite) | CLI | P0 |
| MEV-TC-B005 | `flutter test integration_test/` | Device + Firebase | P1 |
| MEV-TC-B006 | Android release build | CI/device | P1 |
| MEV-TC-B007 | iOS release build | CI/device | P1 |

## 2. Static Analysis

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-S001 | Dart analyzer zero errors | `flutter analyze` |
| MEV-TC-S002 | Linter warnings triage | Analyzer output |
| MEV-TC-S003 | Deprecated API usage | Grep + analyzer |
| MEV-TC-S004 | Dead/orphan screens | Router vs file inventory |
| MEV-TC-S005 | TODO/FIXME in `lib/` | Grep |

## 3. Authentication

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-A001 | Email login success | Widget + unit |
| MEV-TC-A002 | Email login wrong password | Widget |
| MEV-TC-A003 | Email register + validation | Widget |
| MEV-TC-A004 | Google sign-in | Unit + device |
| MEV-TC-A005 | Apple sign-in (iOS) | Device |
| MEV-TC-A006 | Phone OTP send | Widget + device |
| MEV-TC-A007 | Phone OTP verify | Widget + device |
| MEV-TC-A008 | Spotify OAuth login | Device + CF |
| MEV-TC-A009 | Logout clears session | Widget |
| MEV-TC-A010 | Re-login restores profile | Device |
| MEV-TC-A011 | Auth redirect / splash gate | Unit + widget |
| MEV-TC-A012 | Password reset flow | Widget |

## 4. Registration & Age (18+)

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-R001 | Age validator 17 rejected | Unit |
| MEV-TC-R002 | Exact 18th birthday accepted | Unit |
| MEV-TC-R003 | Future birth date rejected | Unit |
| MEV-TC-R004 | Onboarding age step UI | Widget |

## 5. Onboarding

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-O001 | Full onboarding flow | Widget |
| MEV-TC-O002 | Photo minimum (3+) | Unit + widget |
| MEV-TC-O003 | Interest selection limits | Widget |
| MEV-TC-O004 | Relationship goal picker | Widget |
| MEV-TC-O005 | Lifestyle picker | Widget |
| MEV-TC-O006 | `completeOnboarding` CF | Integration |
| MEV-TC-O007 | Back / skip behavior | Manual |

## 6. Profile & Profile Edit

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-P001 | Profile tab loads data | Widget |
| MEV-TC-P002 | Edit profile sections | Widget + manual |
| MEV-TC-P003 | Unsaved changes dialog | Code review |
| MEV-TC-P004 | Single Firestore write on save | Code review |
| MEV-TC-P005 | Profile answers page | Widget |
| MEV-TC-P006 | Discovery preferences link | Manual |

## 7. Photo Upload

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-PH001 | Upload pipeline | Unit |
| MEV-TC-PH002 | Moderation pending path | Security test |
| MEV-TC-PH003 | Min/max photo count | Unit |
| MEV-TC-PH004 | Storage rules owner-only | Security test |
| MEV-TC-PH005 | Large image / cancel | Device |

## 8. Discover & Swipe

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-D001 | Candidate loading | Unit + widget |
| MEV-TC-D002 | Cursor pagination | Unit |
| MEV-TC-D003 | Swipe like/pass/super-like | Unit + widget |
| MEV-TC-D004 | Location permission flows | Widget |
| MEV-TC-D005 | Empty / seen everyone states | Widget |
| MEV-TC-D006 | Filters (age, distance, gender) | Unit |
| MEV-TC-D007 | Blocked users excluded | Unit + CF |
| MEV-TC-D008 | 90-day activity filter | Unit |
| MEV-TC-D009 | Swipe animation / no duplicate action | Widget |
| MEV-TC-D010 | `getDiscoveryCandidates` CF | Integration |

## 9. Compatibility Engine

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-C001 | Score not fake 0% | Unit |
| MEV-TC-C002 | Partial data handling | Unit |
| MEV-TC-C003 | A+B = B+A deterministic | Unit |
| MEV-TC-C004 | Server score parse (string) | Unit |
| MEV-TC-C005 | Breakdown fallback | Unit |
| MEV-TC-C006 | Discover badge states | Widget |
| MEV-TC-C007 | Why You Match sheet data | Widget + manual |
| MEV-TC-C008 | Hidden compatibility card | Unit |
| MEV-TC-C009 | Profile update invalidates cache | Code review |

## 10. Matching Engine

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-M001 | Mutual like creates match | Unit + CF |
| MEV-TC-M002 | One-way like no match | Unit |
| MEV-TC-M003 | Duplicate match prevention | Unit |
| MEV-TC-M004 | Match celebration UI | Widget |
| MEV-TC-M005 | `recordDiscoveryDecision` CF | Integration |

## 11. Relationship Questions

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-Q001 | Offer card copy (l10n) | Widget |
| MEV-TC-Q002 | 3-question flow | Widget |
| MEV-TC-Q003 | Answer save via CF | Unit |
| MEV-TC-Q004 | Exact triple matching | Unit |
| MEV-TC-Q005 | Cooldown after dismiss | Unit |

## 12. Chat

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-CH001 | Send text message | Unit |
| MEV-TC-CH002 | Match-only send guard | Unit |
| MEV-TC-CH003 | Pagination (30 limit) | Unit |
| MEV-TC-CH004 | Typing debounce | Unit |
| MEV-TC-CH005 | Voice / image message | Code review |
| MEV-TC-CH006 | Realtime listener lifecycle | Code review |
| MEV-TC-CH007 | Block after chat | Manual |

## 13. Block & Report

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-BL001 | Block user CF | Unit |
| MEV-TC-BL002 | Blocked list UI | Widget |
| MEV-TC-BL003 | Report page submit | Widget + CF |
| MEV-TC-BL004 | Safety compliance | Unit |

## 14. Account Deletion

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-DEL001 | Delete UI reachable from Settings | **Manual** |
| MEV-TC-DEL002 | `deleteUserAccount` CF | Code review |
| MEV-TC-DEL003 | Auth user removed | Integration |
| MEV-TC-DEL004 | Firestore + Storage cleanup | CF review |

## 15. Verification (Sumsub)

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-V001 | Verify profile screen | Widget |
| MEV-TC-V002 | Sumsub SDK launch | **Device + credentials** |
| MEV-TC-V003 | Webhook status update | **Staging CF** |
| MEV-TC-V004 | Verified badge on profile | Widget |

## 16. Payments (Boost IAP)

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-PAY001 | Boost screen UI | Widget |
| MEV-TC-PAY002 | Product load | Device sandbox |
| MEV-TC-PAY003 | `verifyBoostPurchase` CF | Staging |
| MEV-TC-PAY004 | Active boost in discover | Unit |

## 17. Notifications

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-N001 | FCM token registration | Device |
| MEV-TC-N002 | Match notification CF | Staging |
| MEV-TC-N003 | Message notification CF | Staging |
| MEV-TC-N004 | Notification settings page | Widget |

## 18. Music / Spotify

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-MU001 | Music tab UI | Widget |
| MEV-TC-MU002 | Spotify link | Device + CF |
| MEV-TC-MU003 | `spotifyLinkMusic` CF deployed | **Code audit** |
| MEV-TC-MU004 | Music compatibility badge | Widget |

## 19. Localization

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-L001 | EN locale all major screens | Widget |
| MEV-TC-L002 | TR locale all major screens | Widget |
| MEV-TC-L003 | Language switch live | Widget |
| MEV-TC-L004 | No hardcoded user strings | Grep |

## 20. Theme & Animations

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-UI001 | Dark theme contrast | Widget |
| MEV-TC-UI002 | Swipe animations | Widget |
| MEV-TC-UI003 | Rive fallbacks in tests | Unit |
| MEV-TC-UI004 | Page transitions | Unit |

## 21. Navigation

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-NAV001 | All `AppRoutes` registered | Code audit |
| MEV-TC-NAV002 | Auth redirect | Unit |
| MEV-TC-NAV003 | Shell tabs (4) | Manual |
| MEV-TC-NAV004 | Deep link chat route | Manual |
| MEV-TC-NAV005 | Orphan pages not routed | Code audit |

## 22. Firebase & Security

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-F001 | Firestore production rules tests | Unit (33) |
| MEV-TC-F002 | Storage production rules | Unit |
| MEV-TC-F003 | Coordinate isolation in discovery | Unit |
| MEV-TC-F004 | Client cannot write likes/purchases | Rules review |
| MEV-TC-F005 | CF export completeness | Code audit |

## 23. Performance & Memory

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-PERF001 | Discover pagination | Code review |
| MEV-TC-PERF002 | Chat list rebuild | Code review |
| MEV-TC-PERF003 | Image thumb-first | Code review |
| MEV-TC-PERF004 | Listener dispose | Code review |
| MEV-TC-PERF005 | DevTools frame rate | **Device** |

## 24. Edge Cases

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-E001 | Double-tap logout | Widget |
| MEV-TC-E002 | Rapid swipe | Manual |
| MEV-TC-E003 | Network failure handling | Manual |
| MEV-TC-E004 | Empty Firestore fields | Unit |

## 25. Regression

| ID | Scenario | Method |
|----|----------|--------|
| MEV-TC-REG001 | Full `flutter test` green | CI |
| MEV-TC-REG002 | Security suite green | CI |
| MEV-TC-REG003 | No new analyzer errors | CI |

---

## Test Environments

| Env | Use |
|-----|-----|
| Local unit/widget | `flutter test` |
| Android emulator | `emulator-5554` available |
| Production Firebase | **Requires dedicated test accounts — not used in this audit** |
| Sumsub sandbox | **Credentials required — NOT TESTABLE** |
| IAP sandbox | **Store accounts required — NOT TESTABLE** |

## Entry / Exit Criteria

**Entry:** Clean checkout, `flutter pub get` succeeds.  
**Exit:** All P0/P1 scenarios executed or marked NOT TESTABLE with evidence; bug report filed; production readiness assessed.
