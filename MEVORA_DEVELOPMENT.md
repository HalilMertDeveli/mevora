# MEVORA

## Flutter Dating Application — Development Documentation

**Version:** 1.0.0  
**Platform:** iOS + Android  
**Framework:** Flutter  
**Backend:** Firebase  
**Architecture:** Feature-First + Clean Architecture  
**Status:** Development  

---

# 1. PROJECT OVERVIEW

Mevora is a modern mobile dating application for iOS and Android.

The application will provide a familiar swipe-based dating experience inspired by modern dating applications, while maintaining its own brand identity, UI/UX, architecture, source code, recommendation algorithm, and compatibility system.

The application must NOT copy proprietary branding, source code, assets, text, or exact visual design from Tinder or any other application.

Core product idea:

> **Mevora helps users discover people they are likely to connect with, not simply people nearby.**

Primary differentiator: **Mevora Compatibility Engine**

Users will see potential matches plus compatibility percentage, shared interests, relationship goal compatibility, common lifestyle characteristics, and reasons why the person was recommended.

---

# 2. PRODUCT GOALS

1. Smooth swipe-based discovery.
2. Detailed profiles.
3. Compatible user recommendations.
4. Like, Pass, and Super Like.
5. Automatic Match when two users Like each other.
6. Matched-user communication.
7. Strong safety and reporting.
8. User data protection.
9. iOS and Android.
10. Production-ready for App Store and Google Play.
11. Scalable for future growth.
12. Support future monetization.

---

# 3. TECHNOLOGY STACK

**Mobile:** Flutter, Dart

**Backend:** Firebase Authentication, Cloud Firestore, Firebase Storage, Cloud Functions, Cloud Messaging, App Check, Crashlytics, Analytics

**Development:** Firebase Emulator Suite, Flutter Test, Integration Test

---

# 4. DEVELOPMENT PRINCIPLES

1. Do not build everything at once. Develop phase by phase.
2. After every completed phase run `flutter analyze` and `flutter test`. Fix all errors before moving on.
3. Production-quality code only.
4. Keep business logic outside UI:

```text
Presentation → Controller / State → Repository → Data Source → Firebase
```

5. Minimize dependencies. Prefer Flutter APIs and existing packages.
6. Security first. Never use `allow read, write: if true;`. Never trust the client with sensitive business logic.
7. No secrets in source code: API secrets, private keys, service accounts, or production secrets.

---

# 5. PROJECT ARCHITECTURE

Feature-first layout:

```text
lib/
├── core/          constants, config, theme, routing, errors, utils, extensions, services
├── features/      authentication, onboarding, profile, discovery, matching,
│                  chat, notifications, safety, settings, subscription
│                  each with data / domain / presentation
├── shared/        widgets, models, components, animations
└── main.dart
```

---

# 6. DEVELOPMENT PHASES

```text
Phase 1  Project Architecture
Phase 2  Firebase Configuration
Phase 3  Authentication
Phase 4  Onboarding
Phase 5  Profile
Phase 6  Discovery / Swipe
Phase 7  Compatibility Engine
Phase 8  Like / Pass / Super Like
Phase 9  Matching
Phase 10 Chat
Phase 11 Notifications
Phase 12 Safety & Moderation
Phase 13 Settings & Account Deletion
Phase 14 Subscription Architecture
Phase 15 Admin System
Phase 16 Security
Phase 17 Testing
Phase 18 Performance
Phase 19 Analytics & Crash Reporting
Phase 20 Store Preparation
Phase 21 QA
Phase 22 Production Release
```

Do not skip phases.

---

# 7. PHASE 1 — PROJECT ARCHITECTURE

Create the Flutter project. Configure application name, package name, environments, routing, theme, error handling, logging, and reusable components.

Design-system components:

```text
MevoraButton
MevoraTextField
MevoraCard
MevoraAvatar
MevoraChip
MevoraDialog
MevoraBottomSheet
MevoraLoading
MevoraErrorView
MevoraEmptyState
```

Do not create random UI styles in individual screens.

---

# 8. PHASE 2 — FIREBASE CONFIGURATION

Separate environments: development, staging, production. Each has its own Firebase configuration.

Configure Authentication, Firestore, Storage, Cloud Functions, Cloud Messaging, Crashlytics, Analytics, and App Check.

Configure Firebase Emulator Suite for development. Do not use production data during development.

---

# 9. PHASE 3 — AUTHENTICATION

Splash, email registration, email login, password reset, logout, Google Sign-In, Apple Sign-In.

Unauthenticated users go to Login/Register. Authenticated users with incomplete profiles go to Onboarding. Complete profiles go to Discovery.

Authentication state must be handled globally.

---

# 10. PHASE 4 — ONBOARDING

Multi-step flow: first name, birth date, gender, interested in, city/location, profile photos, bio, interests, relationship goal.

Only adult users are allowed. If location permission is denied, allow manual city selection. Do not make unnecessary permissions mandatory.

---

# 11. PHASE 5 — USER PROFILE

User model fields: id, name, birthDate, gender, interestedIn, bio, city, location, photos, interests, relationshipGoal, isVerified, isActive, createdAt, lastActiveAt.

Implement profile view, edit profile, add/remove/reorder photos, edit bio/interests/preferences. Optimize photos before upload.

---

# 12. PHASE 6 — DISCOVERY

Swipe screen cards show photo, name, age, city, bio, interests, and compatibility %.

Swipe right = Like, left = Pass, up = Super Like, tap = profile details.

Include smooth animations, loading/empty/error states. Do not copy Tinder’s exact visual design.

---

# 13. PHASE 7 — MEVORA COMPATIBILITY ENGINE

Initial weights: Shared Interests 25%, Relationship Goal 20%, Distance 20%, Age Preference 15%, Lifestyle 10%, Activity 10%.

Keep the algorithm modular and outside UI. Backend returns compatibilityScore, sharedInterests, and compatibilityReasons. Design for a later ML/AI replacement.

---

# 14. PHASE 8 — LIKE / PASS / SUPER LIKE

Prevent duplicate actions, self-like, and interaction with blocked users. The client requests the action; the backend validates and processes it.

---

# 15. PHASE 9 — MATCHING

A match occurs when User A likes User B and User B likes User A. Store `matches/{matchId}` with id, userIds, createdAt, lastMessage, lastMessageAt, isActive. Show a MATCH screen and a dedicated Matches list.

---

# 16. PHASE 10 — CHAT

Only matched users may communicate. MVP: text, emoji, timestamps, read status, typing indicator, online status. Only conversation participants may access a conversation.

---

# 17. PHASE 11 — NOTIFICATIONS

FCM for New Match, New Message, Super Like, and Safety notifications. Foreground/background handling, tap navigation, device token management. Notification permission is optional for core use.

---

# 18. PHASE 12 — SAFETY & MODERATION

Report, Block, Unmatch, Report Message, Report Profile.

Report reasons: Fake Profile, Harassment, Inappropriate Content, Spam, Scam, Underage, Other.

Blocking removes the user from discovery and prevents interaction, messaging, profile views, and future recommendations.

Photo upload flow: Select → Validate → Upload → Moderation → Publish or Reject. Never publicly display rejected images. Design for a later AI moderation service.

---

# 19. PHASE 13 — SETTINGS

Edit Profile, Discovery Preferences, Notifications, Privacy, Blocked Users, Help, Terms, Privacy Policy, Community Guidelines, Delete Account, Logout.

Account deletion must be real deletion/anonymization, not only `isActive = false`.

Initial discovery filters: Age, Distance, Gender, Relationship Goal.

---

# 20. PHASE 14 — SUBSCRIPTION ARCHITECTURE

Prepare architecture for future premium features. Do not implement monetization before the core dating experience is stable.

---

# 21. PHASE 15 — ADMIN SYSTEM

Separate admin application. Dashboard metrics, user management, and report review. Admin permissions must never be available to normal users.

---

# 22. PHASE 16 — FIRESTORE SECURITY

Security rules must enforce ownership. Users can edit only their own profile. Likes cannot impersonate another user. Only matched users can read/write messages. Clients cannot arbitrarily create matches. Blocked users cannot interact. Never `allow read, write: if true;`.

---

# 23. PHASE 17–19 — TESTING, PERFORMANCE, ANALYTICS

Unit-test compatibility, age, distance, matching, validation, and filtering. Widget-test core screens. Integration-test registration, matching, chat, and safety flows.

Paginate discovery. Never load unlimited profiles. Cache and optimize images.

Track product events without unnecessary sensitive data. Configure Crashlytics for Flutter, native, backend, and critical network failures.

---

# 24. ENVIRONMENTS AND PACKAGE IDENTIFIERS

Environments: Development, Staging, Production (`mevora-dev`, `mevora-staging`, `mevora-production`). Never mix production and development databases.

```text
Android: com.mevora.app
iOS:     com.mevora.app
```

If the package name is already taken, stop and report the conflict before changing it.

---

# 25. MVP DEFINITION

The first production MVP MUST contain:

Registration, Login, Google Login, Apple Login, Onboarding, Profile, Profile Photos, Discovery, Swipe, Like, Pass, Super Like, Compatibility Score, Match, Chat, Push Notifications, Block, Report, Unmatch, Settings, Privacy Policy, Terms, Community Guidelines, Account Deletion, Firebase Security, Crash Reporting, Analytics.

Do NOT add before the MVP is stable: Video Chat, Voice Chat, AI Dating Assistant, Advanced AI Matching, Live Streaming, Complex Subscription System, Large Social Feed, Stories.

---

# 26. CURSOR AGENT INSTRUCTIONS

When starting a new phase:

1. Read this document.
2. Inspect the current repository.
3. Inspect the existing architecture.
4. Determine what has already been implemented.
5. Do not overwrite working code unnecessarily.
6. Implement only the requested phase.
7. Follow the established architecture.
8. Write tests.
9. Run `flutter analyze` and `flutter test`.
10. Fix all errors.
11. Summarize what was implemented.
12. Identify any remaining issues.
13. Do not automatically start the next phase.

If a requirement is ambiguous: inspect existing code first, make the safest architectural decision, document the decision, and do not rewrite unrelated modules.

---

# 27. FINAL PRODUCT PRINCIPLE

> **Mevora doesn't just help you find people. It helps you find compatible people.**

Every recommended profile should answer: **Why am I seeing this person?**

---

# END OF MEVORA DEVELOPMENT DOCUMENTATION
