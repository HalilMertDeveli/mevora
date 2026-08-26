# Question & Answer Profile Architecture

## Overview

Mevora's relationship question system powers discovery compatibility matching. This document describes how **profile-visible answers** are persisted and displayed without changing matching behavior.

## Existing Question System (unchanged)

| Layer | Location |
|---|---|
| Catalog | `lib/features/relationship/data/catalog/relationship_questions.dart` |
| Discovery UI | `RelationshipController`, `RelationshipQuestionCard` |
| Profile edit | `ProfileAnswersPage` |
| Matching writes | Cloud Function `saveRelationshipAnswer` |
| Matching reads | `users/{uid}/relationshipAnswers`, `relationshipMatch/summary` |

Matching continues to use `questionId → answerId` (`a`/`b`/`c`) maps. The catalog supplies localized question/answer text at display time.

## Profile Answer Persistence (new layer)

When a user saves an answer through the existing flow:

```
Question UI → saveAnswer() → saveRelationshipAnswer (CF)
                                    ├── relationshipAnswers/{questionId}  (matching)
                                    ├── relationshipMatch/summary           (matching)
                                    └── questionAnswers/{questionId}        (profile)
```

### Firestore structure

`users/{uid}/questionAnswers/{questionId}`

```json
{
  "questionId": "rq_042",
  "answerId": "b",
  "isVisible": true,
  "createdAt": "<server timestamp>",
  "updatedAt": "<server timestamp>"
}
```

- Document ID = `questionId` (no duplicates; updates overwrite)
- Display text is resolved client-side from `RelationshipQuestionCatalog` using `questionId` + `answerId`
- `isVisible: false` hides from other users but **does not** remove matching data

### Cloud Functions

| Callable | Purpose |
|---|---|
| `saveRelationshipAnswer` | Existing; now also upserts `questionAnswers` |
| `syncProfileQuestionAnswers` | Backfill profile docs from matching answers |
| `updateQuestionAnswerVisibility` | Toggle `isVisible` without touching matching |

## Flutter architecture

```
Answer UI (unchanged)
    ↓
RelationshipRepository.saveAnswer()     → matching
    ↓
ProfileQuestionAnswerRepository         → profile reads / visibility
    ↓
FirebaseProfileQuestionAnswerDataSource → Firestore + CF
```

| Component | Path |
|---|---|
| Model | `lib/features/profile/domain/models/profile_question_answer.dart` |
| Repository | `lib/features/profile/domain/repositories/profile_question_answer_repository.dart` |
| Data source | `lib/features/profile/data/datasources/firebase_profile_question_answer_data_source.dart` |
| Display helper | `lib/features/profile/domain/services/profile_question_answer_display.dart` |
| Profile section widget | `lib/features/profile/presentation/widgets/profile_question_answers_section.dart` |

Wired through `RelationshipScope.profileAnswers`.

## Profile UI

| Screen | Behavior |
|---|---|
| Profile tab | Owner preview (up to 3) + edit link |
| Edit profile | Same section with edit action |
| Discovery profile details | Other user's visible answers only |
| Profile answers editor | Answer chips + "Show on profile" toggle |

## Privacy

- `isVisible == true`: readable by owner and **actively matched** users only
- `isVisible == false`: owner-only read; hidden from profile; matching data unchanged
- Non-matched users cannot read `questionAnswers` (Firestore rules + client gate)
- Unmatch sets `matches/{id}.isActive = false` → access revoked in rules and UI
- Blocked pairs cannot match; `hasActiveMatchWith` checks `isBlockedPair`

### Security rules

```javascript
function hasActiveMatchWith(otherUid) {
  return isAuthenticated()
    && otherUid != request.auth.uid
    && !isBlockedPair(request.auth.uid, otherUid)
    && exists(/databases/$(database)/documents/matches/$(canonicalMatchId(...)))
    && get(...).data.isActive == true
    && request.auth.uid in get(...).data.userIds;
}

match /questionAnswers/{questionId} {
  allow read: if isOwner(userId)
    || (hasActiveMatchWith(userId) && resource.data.isVisible == true);
}
```

## Localization

Keys: `questionAnswersTitle`, `questionAnswersEmpty`, `seeAllAnswers`, `showOnProfile`, `questionAnswersLoadError`

## Testing

- `test/features/profile/profile_question_answers_test.dart`
- `test/features/relationship/relationship_catalog_quality_test.dart` (regression)
- Firestore rules test for `questionAnswers`

## Regression checklist

- [ ] Questions still load from catalog unchanged
- [ ] `saveRelationshipAnswer` still updates matching summary
- [ ] Compatibility scores unchanged
- [ ] Profile shows correct localized text per `questionId`
- [ ] Hidden answers excluded from other-user profile reads
- [ ] Hidden answers still count for matching
