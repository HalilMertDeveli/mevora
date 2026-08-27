const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  shapePartnerQuestionAnswers,
} = require("../lib/premiumQuestionAnswersShape.js");

describe("partner question answers premium gate", () => {
  const rows = [
    {questionId: "rq_001", answerId: "a", isVisible: true},
    {questionId: "rq_002", answerId: "b", isVisible: true},
    {questionId: "rq_003", answerId: "c", isVisible: false},
  ];

  it("unmatched clients receive no questions or answers", () => {
    const shaped = shapePartnerQuestionAnswers({
      matched: false,
      isPremium: false,
      rows,
    });
    assert.equal(shaped.locked, true);
    assert.equal(shaped.matchRequired, true);
    assert.equal(shaped.premiumRequired, false);
    assert.deepEqual(shaped.questions, []);
    assert.deepEqual(shaped.answers, []);
  });

  it("free matched clients get question ids only — never answerId", () => {
    const shaped = shapePartnerQuestionAnswers({
      matched: true,
      isPremium: false,
      rows,
    });
    assert.equal(shaped.locked, true);
    assert.equal(shaped.matchRequired, false);
    assert.equal(shaped.premiumRequired, true);
    assert.equal(shaped.isPremium, false);
    assert.deepEqual(shaped.questions, [
      {questionId: "rq_001"},
      {questionId: "rq_002"},
    ]);
    assert.deepEqual(shaped.answers, []);
    for (const q of shaped.questions) {
      assert.equal(Object.keys(q).join(","), "questionId");
    }
  });

  it("premium matched clients receive answer fields", () => {
    const shaped = shapePartnerQuestionAnswers({
      matched: true,
      isPremium: true,
      rows,
    });
    assert.equal(shaped.locked, false);
    assert.equal(shaped.premiumRequired, false);
    assert.equal(shaped.isPremium, true);
    assert.equal(shaped.answers.length, 2);
    assert.equal(shaped.answers[0].answerId, "a");
    assert.equal(shaped.answers[1].answerId, "b");
    assert.deepEqual(shaped.questions.map((q) => q.questionId), [
      "rq_001",
      "rq_002",
    ]);
  });

  it("hidden answers never appear in free or premium payloads", () => {
    const free = shapePartnerQuestionAnswers({
      matched: true,
      isPremium: false,
      rows,
    });
    const premium = shapePartnerQuestionAnswers({
      matched: true,
      isPremium: true,
      rows,
    });
    assert.equal(
      free.questions.some((q) => q.questionId === "rq_003"),
      false,
    );
    assert.equal(
      premium.answers.some((a) => a.questionId === "rq_003"),
      false,
    );
  });
});
