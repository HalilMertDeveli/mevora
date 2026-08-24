# Question & Answer QA Report

**Date:** 2026-08-23  
**Scope:** Simplify & diversify relationship Q&A content — keep UI, matching engine, Firebase answer storage (`questionId → answerId`).

---

## What changed

| Area | Change |
| --- | --- |
| Catalog | Regenerated **111** short, fun, bilingual questions |
| Answers | Per-question short A/B/C (`choiceAnswers`) — no shared Likert templates |
| Categories | `RelationshipContentCategory`: relationship / fun / dailyLife / personality / lifestyle |
| Duplicates | Catalog validates unique ids, labels, answer sets, **semantic prompt twins** |
| Selection | `answeredIds` + semantic twins blocked; diverse fallback triple |
| Matching | **Unchanged** — still compares stable `a`/`b`/`c` answer ids |

### Content mix (approx.)

- ~35% relationship / flört  
- ~25% fun / funny  
- ~20% daily life  
- ~10% personality  
- ~10% lifestyle (food / music / travel / movies)

Examples:

- TR: `İlk buluşmada kahve mi, yemek mi?` → Kahve / Yemek / Yürüyüş  
- TR: `Zombi istilasında sevgilini kurtarır mısın?`  
- TR: `Çay mı kahve mi?`  
- EN: `Who should text first?`

---

## QUESTION & ANSWER QA

| Check | Result |
| --- | --- |
| Same question repeats for a user | **PASS** (`answeredIds` + `blockedQuestionIds`) |
| Same meaning, different wording | **PASS** (semantic key, e.g. çay/kahve) |
| Duplicate answers in one question | **PASS** |
| Empty / null answers | **PASS** |
| Same answer list copied to every question | **PASS** (unique set signatures) |
| Overly long academic prompts | **PASS** (≤90 TR / ≤100 EN) |
| Short answers | **PASS** (≤48 TR chars) |
| Fun + relationship + daily mix | **PASS** |
| Turkish characters | **PASS** |
| English localization | **PASS** (natural pairs, not word-for-word) |
| Matching Engine | **PASS** (answerId-based; tests green) |
| Firebase architecture | **PASS** (still stores ids only) |
| UI unchanged | **PASS** (same cards / buttons) |
| 50+ question sample | **PASS** (111 questions; full suite) |

---

## Tests

`flutter test test/features/relationship/` — **all passed** (41)

Includes catalog quality, semantic duplicates, session skip of answered ids, matching, prompt/offer UI.

---

## Files

- `tools/generate_relationship_catalog.dart` — new short bank  
- `lib/features/relationship/data/catalog/relationship_catalog_entries.dart` — generated  
- `lib/features/relationship/data/catalog/relationship_questions.dart` — category + semantic helpers  
- `lib/features/relationship/data/catalog/relationship_answer_builders.dart` — `choiceAnswers`  
- `lib/features/relationship/domain/services/relationship_question_sets.dart` — blocked/diverse selection  
- `test/features/relationship/relationship_catalog_quality_test.dart`  
- `test/features/relationship/relationship_answer_ui_test.dart`

---

## Note on existing user answers

Stored answers remain `questionId → answerId`. Old long-copy labels are gone from the client catalog; ids `a`/`b`/`c` stay valid. Users who already answered `rq_001`… keep those ids and will not be shown those questions again.
