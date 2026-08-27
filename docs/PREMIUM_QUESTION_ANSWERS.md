# Premium Question Answers Privacy

## Sharing rules

| What | Who can see it |
|---|---|
| **Question text** (catalog prompts) | Everyone who can open the peer Q&A section after an active match (Free + Premium) |
| **Answer text / answerId** | **Premium only**, and only when there is an **active match** |
| Own answers | Owner always (own Firestore `questionAnswers`) |
| Matching answers | Never client-shared; Cloud Functions use private `relationshipAnswers` for scoring |

Free UI: question prompts remain visible; each answer slot shows a Premium lock CTA.  
Premium UI: question + answer.

## Security model

1. **Firestore rules** — `users/{uid}/questionAnswers/{questionId}` is **owner-read only**. Peers cannot query peer answer docs (no answerId leak to free clients). There is no client-side `hasActiveMatchWith` peer-read path.
2. **Cloud Function** `getPartnerQuestionAnswers` — the only peer unlock path:
   - Requires auth
   - Requires active match (`matches/{canonicalId}.isActive`)
   - Free + matched: returns `questions: [{questionId}]` only; `answers: []`
   - Premium + matched: returns full `answers` with `questionId` / `answerId` / `isVisible`
3. **Matching engine unchanged** — still dual-writes / reads `relationshipAnswers` for compatibility scoring. Catalog texts/options are unchanged.
4. **Flutter** — peer `ProfileQuestionAnswersSection` loads via CF only (never Firestore-watches peer `questionAnswers`). Hardening:
   - `_subscribeAnswers` refuses non-owner and redirects to CF fetch
   - Free payload parser strips `answers` even if a buggy payload includes them
   - “See all” sheet strips `answerId` when `premiumLocked`
   - Discovery / chat surfaces reuse the same section (no alternate peer Firestore path)

## Intent for rules reviewers

- `relationshipAnswers`: owner-only (unchanged) — matching private.
- `questionAnswers`: owner-only client read — profile answers private at rest; CF serves gated views.

## Tests

- `functions/test/premiumQuestionAnswersGate.test.cjs` — CF shape gate
- `test/features/profile/partner_question_answers_gate_test.dart` — Flutter payload parser
- `test/features/profile/profile_question_answers_section_test.dart` — Free lock / Premium unlock UI
- `test/security/firestore_production_rules_test.dart` — owner-only `questionAnswers` rule
