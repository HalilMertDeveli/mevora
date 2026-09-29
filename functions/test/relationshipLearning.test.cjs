const {beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

const db = createFakeFirestore();
installFirebaseAdminStubs({db});

const catalog = require("../lib/relationshipLearning/catalog.js");
const {PROGRESSIVE, DECLARED, ANSWER_WRITE_LIMIT} = require("../lib/relationshipLearning/config.js");
const model = require("../lib/relationshipLearning/model.js");
const {learningStatePath, markLearningRequired} = require("../lib/relationshipLearning/store.js");
const {
  getRelationshipLearningState,
  saveRelationshipLearningAnswer,
  skipOnboardingHumor,
  snoozeRelationshipLearningPrompt,
} = require("../lib/relationshipLearning/functions.js");
const {PERSONALIZATION_DIMENSIONS, LEARNING, SIGNAL_STRENGTHS} = require("../lib/personalization/config.js");
const {
  loadPersonalizationContext,
  personalizationProfilePath,
  recordLearningEvent,
} = require("../lib/personalization/store.js");
const {resetMyPersonalization} = require("../lib/personalization/functions.js");
const {relationshipScoreForPair} = require("../lib/relationshipMatch.js");
const {getMevoraPicks} = require("../lib/picks/index.js");

const DAY = 86_400_000;
const T0 = Date.UTC(2026, 8, 1, 12, 0, 0);
const HUMOR_HIGH = {relationship: 50, values: 50, lifestyle: 50, interests: 50, music: 50, humor: 95};

function answerAll(state, questions, answerId = "a", start = T0) {
  let current = state;
  questions.forEach((question, index) => {
    const outcome = model.applyAnswer(current, question.id, answerId, start + index * 1000);
    assert.equal(outcome.ok, true, `answer ${question.id}`);
    current = outcome.state;
  });
  return current;
}

function stateAfterInitial(nowMs = T0) {
  return answerAll(model.emptyLearningState(), catalog.initialQuestions(), "a", nowMs);
}

async function stored(uid) {
  return (await db.doc(learningStatePath(uid)).get()).data();
}

beforeEach(() => {
  db.reset({
    "users/me": {uid: "me"},
    "users/other": {uid: "other"},
    "profiles/me": {relationshipGoal: "longTerm", interests: ["a", "b", "c"]},
    "profiles/other": {relationshipGoal: "longTerm", interests: ["a", "b", "c"]},
  });
});

describe("relationship learning catalog", () => {
  it("asks exactly 15 initial questions, in a stable order", () => {
    const initial = catalog.initialQuestions();
    assert.equal(initial.length, 15);
    assert.equal(catalog.INITIAL_QUESTION_COUNT, 15);
    assert.deepEqual(initial.map((q) => q.order), [...Array(15).keys()].map((i) => i + 1));
  });

  it("gives every question a stable unique id, a version and three distinct options", () => {
    const ids = new Set();
    for (const question of catalog.LEARNING_QUESTIONS) {
      assert.match(question.id, catalog.LEARNING_QUESTION_ID_PATTERN);
      assert.ok(!ids.has(question.id), `duplicate ${question.id}`);
      ids.add(question.id);
      assert.ok(question.version >= 1);
      assert.deepEqual(question.options.map((o) => o.id), ["a", "b", "c"]);
      for (const text of [question.prompt, ...question.options.map((o) => o.label)]) {
        assert.ok(text.tr.trim().length > 0 && text.en.trim().length > 0);
        assert.ok(text.tr.length <= 70 && text.en.length <= 80, `too long: ${text.en}`);
      }
      assert.ok(PERSONALIZATION_DIMENSIONS.includes(question.dimension));
      if (question.kind === "importance") {
        assert.deepEqual(question.options.map((o) => o.importance), ["high", "medium", "low"]);
      }
    }
  });

  it("covers every compatibility dimension in the initial set, with one importance question each", () => {
    const initial = catalog.initialQuestions();
    for (const dimension of PERSONALIZATION_DIMENSIONS) {
      assert.ok(initial.some((q) => q.dimension === dimension), `${dimension} not asked`);
      assert.equal(initial.filter((q) => q.kind === "importance" && q.dimension === dimension).length, 1);
    }
  });

  it("stays away from diagnosis and sensitive traits", () => {
    const banned = /(attachment|anxious|avoidant|diagnos|disorder|depress|therapy|religio|politic|sexual|health|bağlanma|kaygı|terapi|\bdin\b|siyas|cinsel|sağlık)/i;
    for (const question of catalog.LEARNING_QUESTIONS) {
      const texts = [question.prompt, ...question.options.map((o) => o.label)]
        .flatMap((t) => [t.tr, t.en]);
      for (const text of texts) assert.equal(banned.test(text), false, `sensitive wording: ${text}`);
    }
  });

  it("validates answers against the catalog only", () => {
    assert.equal(catalog.isValidLearningAnswer("rl_pace", "a"), true);
    assert.equal(catalog.isValidLearningAnswer("rl_pace", "d"), false);
    assert.equal(catalog.isValidLearningAnswer("rl_nope", "a"), false);
    assert.equal(catalog.isValidLearningAnswer("rq_001", "a"), false);
    assert.equal(catalog.isValidLearningAnswer({}, "a"), false);
  });
});

describe("initial questions: progress, resume and idempotency", () => {
  it("counts progress per answer so a restart resumes where it stopped", () => {
    const eight = answerAll(model.emptyLearningState(), catalog.initialQuestions().slice(0, 8));
    assert.equal(model.initialAnsweredCount(eight), 8);
    assert.equal(model.isInitialComplete(eight), false);
    const reread = model.parseLearningState(JSON.parse(JSON.stringify(model.serializeLearningState(eight))));
    assert.equal(model.initialAnsweredCount(reread), 8);
    const firstOpen = catalog.initialQuestions().findIndex((q) => !reread.answers[q.id]);
    assert.equal(firstOpen, 8, "resumes at question 9");
  });

  it("completes exactly once, and a repeated answer changes nothing", () => {
    const questions = catalog.initialQuestions();
    let state = answerAll(model.emptyLearningState(), questions.slice(0, 14));
    const last = model.applyAnswer(state, questions[14].id, "b", T0 + 99);
    assert.equal(last.completedInitialNow, true);
    state = last.state;
    const completedAt = state.initialCompletedAtMs;
    const replay = model.applyAnswer(state, questions[14].id, "b", T0 + 500);
    assert.equal(replay.changed, false);
    assert.equal(replay.completedInitialNow, false);
    const changedMind = model.applyAnswer(state, questions[0].id, "c", T0 + 600);
    assert.equal(changedMind.changed, true);
    assert.equal(changedMind.completedInitialNow, false);
    assert.equal(changedMind.state.initialCompletedAtMs, completedAt);
    assert.equal(Object.keys(changedMind.state.answers).length, 15, "no duplicate answers");
  });

  it("rejects malformed and foreign answers", () => {
    const state = model.emptyLearningState();
    assert.deepEqual(model.applyAnswer(state, "rl_pace", "z", T0), {ok: false, reason: "invalid-answer"});
    assert.deepEqual(model.applyAnswer(state, "rl_unknown", "a", T0), {ok: false, reason: "invalid-question"});
    assert.deepEqual(model.applyAnswer(state, null, "a", T0), {ok: false, reason: "invalid-question"});
    assert.deepEqual(model.applyAnswer(state, "rl_pace", {$gt: ""}, T0), {ok: false, reason: "invalid-answer"});
  });

  it("drops tampered stored answers instead of trusting them", () => {
    const parsed = model.parseLearningState({
      required: true,
      answers: {rl_pace: {answerId: "z"}, rl_evil: {answerId: "a"}, rl_texting: {answerId: "b", version: 1}},
      initialCompletedAtMs: "soon",
      progressive: {batch: ["rl_pace", "rl_humor_style", 7]},
    });
    assert.deepEqual(Object.keys(parsed.answers), ["rl_texting"]);
    assert.equal(parsed.initialCompletedAtMs, null);
    assert.deepEqual(parsed.progressive.batch, ["rl_humor_style"]);
  });

  it("bounds how many answers one member can write in a window", () => {
    let state = model.emptyLearningState();
    for (let i = 0; i < ANSWER_WRITE_LIMIT.max; i++) {
      const outcome = model.applyAnswer(state, "rl_pace", ["a", "b"][i % 2], T0 + i);
      assert.equal(outcome.ok, true);
      state = outcome.state;
    }
    assert.deepEqual(model.applyAnswer(state, "rl_pace", "c", T0 + 1000), {ok: false, reason: "rate-limited"});
    assert.equal(model.applyAnswer(state, "rl_pace", "c", T0 + ANSWER_WRITE_LIMIT.windowMs + 1).ok, true);
  });

  it("blocks Picks only for new members who have not finished", () => {
    const existing = model.emptyLearningState();
    assert.equal(model.isLearningBlockingPicks(existing), false, "existing members are never blocked");
    const fresh = {...model.emptyLearningState(), required: true};
    assert.equal(model.isLearningBlockingPicks(fresh), true);
    const done = {...stateAfterInitial(), required: true};
    assert.equal(model.isLearningBlockingPicks(done), false);
  });
});

describe("declared preferences", () => {
  it("starts neutral and follows importance answers only", () => {
    const neutral = model.declaredAdjustments(model.emptyLearningState());
    for (const d of PERSONALIZATION_DIMENSIONS) assert.equal(neutral[d], 1);
    let state = model.applyAnswer(model.emptyLearningState(), "rl_humor_importance", "a", T0).state;
    state = model.applyAnswer(state, "rl_music_importance", "c", T0).state;
    state = model.applyAnswer(state, "rl_texting", "a", T0).state; // stance: no weight
    const declared = model.declaredAdjustments(state);
    assert.equal(declared.humor, DECLARED.importance.high);
    assert.equal(declared.music, DECLARED.importance.low);
    assert.equal(declared.values, 1);
    for (const d of PERSONALIZATION_DIMENSIONS) assert.ok(declared[d] >= 0.7 && declared[d] <= 1.3);
  });

  it("reuses what the profile already says when judging confidence", () => {
    const none = model.declaredConfidence(model.emptyLearningState(), model.noProfileSignals());
    const rich = model.declaredConfidence(model.emptyLearningState(), {
      hasRelationshipGoal: true, hasLifestyle: true, hasInterests: true,
      hasMusic: true, humorReady: false, relationshipAnswerCount: 12,
    });
    assert.equal(none.music, 0);
    assert.ok(rich.music > none.music);
    assert.ok(rich.values > rich.relationship);
    assert.equal(rich.humor, 0);
    for (const d of PERSONALIZATION_DIMENSIONS) assert.ok(rich[d] >= 0 && rich[d] <= 1);
  });
});

describe("progressive questions", () => {
  it("prefers the dimensions Mevora knows least about, deterministically", () => {
    const state = stateAfterInitial();
    const confidence = model.declaredConfidence(state, {
      ...model.noProfileSignals(), hasMusic: true, humorReady: false,
    });
    const first = model.selectProgressiveQuestions(state, confidence);
    const again = model.selectProgressiveQuestions(state, confidence);
    assert.deepEqual(first.map((q) => q.id), again.map((q) => q.id));
    assert.equal(first.length, PROGRESSIVE.batchSize);
    // Humor (one initial answer, no calibration) is the weakest dimension.
    assert.equal(first[0].dimension, "humor");
    assert.ok(new Set(first.map((q) => q.dimension)).size >= 2, "a round spreads over dimensions");
    const knownHumor = {...confidence, humor: 1};
    const withoutHumor = model.selectProgressiveQuestions(state, knownHumor);
    assert.notEqual(withoutHumor[0].dimension, "humor");
  });

  it("never serves an answered question again", () => {
    let state = stateAfterInitial();
    const confidence = model.declaredConfidence(state, model.noProfileSignals());
    const seen = new Set();
    for (let round = 0; round < 10; round++) {
      const questions = model.selectProgressiveQuestions(state, confidence);
      if (questions.length === 0) break;
      for (const q of questions) {
        assert.equal(seen.has(q.id), false, `${q.id} asked twice`);
        seen.add(q.id);
      }
      state = answerAll(state, questions, "b");
    }
    assert.equal(seen.size, catalog.progressiveQuestions().length);
    assert.deepEqual(model.selectProgressiveQuestions(state, confidence), []);
  });

  it("keeps a round stable until it is answered", () => {
    const state = stateAfterInitial();
    const confidence = model.declaredConfidence(state, model.noProfileSignals());
    const {state: withRound, created} = model.ensureProgressiveBatch(state, confidence, T0 + DAY);
    assert.equal(created, true);
    const shifted = {...confidence, humor: 1, music: 1};
    const again = model.ensureProgressiveBatch(withRound, shifted, T0 + DAY + 5);
    assert.equal(again.created, false);
    assert.deepEqual(again.state.progressive.batch, withRound.progressive.batch);
  });

  it("has no rounds before the initial set is done", () => {
    const partial = answerAll(model.emptyLearningState(), catalog.initialQuestions().slice(0, 5));
    const result = model.ensureProgressiveBatch(partial, model.declaredConfidence(partial, model.noProfileSignals()), T0);
    assert.equal(result.created, false);
    assert.equal(model.isProgressivePromptDue(partial, T0 + 30 * DAY), false);
  });

  it("is invited only after quiet days, never on an hourly rhythm", () => {
    const done = stateAfterInitial(T0);
    const confidence = model.declaredConfidence(done, model.noProfileSignals());
    const withRound = model.ensureProgressiveBatch(done, confidence, T0).state;
    const completedAt = withRound.initialCompletedAtMs;
    for (let hour = 1; hour < 24; hour++) {
      assert.equal(model.isProgressivePromptDue(withRound, completedAt + hour * 3_600_000), false,
        `due ${hour}h after onboarding`);
    }
    assert.equal(model.isProgressivePromptDue(withRound, completedAt + PROGRESSIVE.firstDelayMs), true);

    // Answer the round: the next one waits the full interval.
    const answeredAt = completedAt + PROGRESSIVE.firstDelayMs + 60_000;
    let state = withRound;
    for (const id of withRound.progressive.batch) {
      const outcome = model.applyAnswer(state, id, "a", answeredAt);
      state = outcome.state;
    }
    assert.deepEqual(state.progressive.batch, []);
    assert.equal(state.progressive.lastBatchCompletedAtMs, answeredAt);
    state = model.ensureProgressiveBatch(state, confidence, answeredAt + 1).state;
    for (let hour = 1; hour < 72; hour++) {
      assert.equal(model.isProgressivePromptDue(state, answeredAt + hour * 3_600_000), false);
    }
    assert.equal(model.isProgressivePromptDue(state, answeredAt + PROGRESSIVE.intervalMs), true);

    // "Not now" hides it again for days.
    const snoozed = {...state, progressive: {...state.progressive, snoozedUntilMs: answeredAt + PROGRESSIVE.intervalMs + PROGRESSIVE.snoozeMs}};
    assert.equal(model.isProgressivePromptDue(snoozed, answeredAt + PROGRESSIVE.intervalMs + DAY), false);
  });

  it("has no scheduler anywhere in relationship learning", () => {
    const dir = path.join(__dirname, "../src/relationshipLearning");
    for (const file of fs.readdirSync(dir)) {
      const source = fs.readFileSync(path.join(dir, file), "utf8");
      assert.equal(/onSchedule|pubsub\.schedule|every \d+ (minutes|hours)/.test(source), false, file);
    }
  });
});

describe("relationship learning callables", () => {
  it("requires sign-in", async () => {
    await assert.rejects(callAs(getRelationshipLearningState, null), /sign-in-required/);
    await assert.rejects(callAs(saveRelationshipLearningAnswer, null, {questionId: "rl_pace", answerId: "a"}),
      /sign-in-required/);
  });

  it("serves the 15 initial questions with saved answers, both languages, no scoring metadata", async () => {
    await callAs(saveRelationshipLearningAnswer, "me", {questionId: "rl_pace", answerId: "b"});
    const state = await callAs(getRelationshipLearningState, "me");
    assert.equal(state.initial.total, 15);
    assert.equal(state.initial.questions.length, 15);
    assert.equal(state.initial.answered, 1);
    assert.equal(state.initial.questions[0].answerId, "b");
    assert.equal(state.initial.questions[1].answerId, null);
    const first = state.initial.questions[0];
    assert.ok(first.prompt.tr && first.prompt.en);
    assert.equal(JSON.stringify(state).includes("importance\":\"high"), false, "no weight mapping leaks");
    assert.equal(state.required, false, "an existing member is never required");
  });

  it("writes only to the caller's own state, whatever the payload claims", async () => {
    await callAs(saveRelationshipLearningAnswer, "me", {
      questionId: "rl_pace", answerId: "a", uid: "other", userId: "other",
    });
    assert.ok((await stored("me")).answers.rl_pace);
    assert.equal(await stored("other"), undefined);
  });

  it("rejects malformed answers and never stores them", async () => {
    for (const payload of [
      {questionId: "rl_pace", answerId: "z"},
      {questionId: "rl_pace"},
      {questionId: "../users/other", answerId: "a"},
      {questionId: "rq_001", answerId: "a"},
      {},
    ]) {
      await assert.rejects(callAs(saveRelationshipLearningAnswer, "me", payload), /invalid/);
    }
    assert.equal(await stored("me"), undefined);
  });

  it("completes the initial set once and survives retries", async () => {
    const questions = catalog.initialQuestions();
    let completions = 0;
    for (const question of questions) {
      for (let attempt = 0; attempt < 2; attempt++) {
        const result = await callAs(saveRelationshipLearningAnswer, "me", {questionId: question.id, answerId: "a"});
        if (result.completedInitialNow) completions += 1;
      }
    }
    assert.equal(completions, 1);
    const state = await callAs(getRelationshipLearningState, "me");
    assert.equal(state.initial.completed, true);
    assert.equal(state.initial.answered, 15);
    assert.equal(Object.keys((await stored("me")).answers).length, 15);
  });

  it("mirrors stance answers into the pair scorer, not importance answers", async () => {
    for (const question of catalog.initialQuestions()) {
      await callAs(saveRelationshipLearningAnswer, "me", {questionId: question.id, answerId: "a"});
      await callAs(saveRelationshipLearningAnswer, "other", {
        questionId: question.id, answerId: question.id === "rl_texting" ? "c" : "a",
      });
    }
    const summary = (await db.doc("users/me/relationshipMatch/summary").get()).data();
    const mirrored = Object.keys(summary.learningAnswers);
    assert.ok(mirrored.includes("rl_pace"));
    assert.equal(mirrored.includes("rl_humor_importance"), false);
    const pair = await relationshipScoreForPair("me", "other");
    const stanceCount = catalog.initialQuestions().filter((q) => q.kind === "stance").length;
    assert.equal(pair.sharedQuestionCount, stanceCount);
    assert.equal(pair.alignedCount, stanceCount - 1);
    assert.ok(pair.topTopics.length > 0);
  });

  it("marks new members as required, create-only, never overwriting progress", async () => {
    await markLearningRequired(db, "newbie");
    assert.equal((await stored("newbie")).required, true);
    await callAs(saveRelationshipLearningAnswer, "me", {questionId: "rl_pace", answerId: "a"});
    await markLearningRequired(db, "me");
    const mine = await stored("me");
    assert.equal(mine.required, false);
    assert.ok(mine.answers.rl_pace);
  });

  it("holds a new member's Picks until the initial set is done", async () => {
    await markLearningRequired(db, "me");
    const blocked = await callAs(getMevoraPicks, "me");
    assert.equal(blocked.status, "empty");
    assert.equal(blocked.emptyReason, "learningRequired");
    assert.equal(blocked.learning.blocksPicks, true);
    for (const question of catalog.initialQuestions()) {
      await callAs(saveRelationshipLearningAnswer, "me", {questionId: question.id, answerId: "a"});
    }
    const open = await callAs(getMevoraPicks, "me");
    assert.notEqual(open.emptyReason, "learningRequired");
    assert.equal(open.learning.initialCompleted, true);
  });

  it("offers a follow-up round only after the initial set, and snoozes it on request", async () => {
    const before = await callAs(getRelationshipLearningState, "me");
    assert.deepEqual(before.progressive.questions, []);
    for (const question of catalog.initialQuestions()) {
      await callAs(saveRelationshipLearningAnswer, "me", {questionId: question.id, answerId: "a"});
    }
    const after = await callAs(getRelationshipLearningState, "me");
    assert.equal(after.progressive.questions.length, PROGRESSIVE.batchSize);
    assert.equal(after.progressive.due, false, "not due on the same day as onboarding");
    const again = await callAs(getRelationshipLearningState, "me");
    assert.deepEqual(again.progressive.questions.map((q) => q.id), after.progressive.questions.map((q) => q.id));
    const snooze = await callAs(snoozeRelationshipLearningPrompt, "me");
    assert.ok(snooze.snoozedUntilMs > Date.now());
    assert.ok((await stored("me")).progressive.snoozedUntilMs > Date.now());
  });
});

describe("declared + observed personalization", () => {
  it("applies declared weights even with interaction learning OFF, and observed ones only when ON", async () => {
    await callAs(saveRelationshipLearningAnswer, "me", {questionId: "rl_humor_importance", answerId: "a"});
    await db.doc(personalizationProfilePath("me")).set({
      algorithmVersion: 1,
      partnerCount: LEARNING.minDistinctPartners,
      dimensions: {music: {adjustment: 1.2, evidence: 10, positive: 10, negative: 0}},
      eventCount: 10,
      updatedAtMs: T0,
    });
    const on = await loadPersonalizationContext(db, "me");
    assert.equal(on.declared.humor, DECLARED.importance.high);
    assert.equal(on.observed.music, 1.2);
    assert.ok(Math.abs(on.adjustments.music - 1.2) < 1e-9);
    await db.doc("userSettings/me").set({personalizeRecommendations: false});
    const off = await loadPersonalizationContext(db, "me");
    assert.equal(off.observed.music, 1);
    assert.equal(off.adjustments.music, 1);
    assert.equal(off.adjustments.humor, DECLARED.importance.high, "the member's own answers still count");
  });

  it("caps what one person can contribute and counts distinct people once", async () => {
    const outcomes = [];
    for (const [type, key] of [
      ["like", "decision"], ["match", "m1"], ["conversationStarted", "m1"],
      ["conversationSurvived", "m1"], ["secondSession", "m1"],
    ]) {
      const result = await recordLearningEvent(db, {
        actorUid: "me", otherUid: "other", type, key,
        strength: SIGNAL_STRENGTHS[type], vector: HUMOR_HIGH, nowMs: T0,
      });
      outcomes.push(result.outcome);
    }
    assert.deepEqual(outcomes.slice(0, 4), ["applied", "applied", "applied", "applied"]);
    assert.equal(outcomes[4], "partnerCap", "one connection cannot keep teaching");
    const profile = (await db.doc(personalizationProfilePath("me")).get()).data();
    assert.equal(profile.partnerCount, 1);
    const partners = await db.collection("users/me/personalizationPartners").get();
    assert.equal(partners.size, 1);
    assert.equal(partners.docs[0].id.includes("other"), false, "partner ids are hashed");
    assert.ok(partners.docs[0].data().strengthSpent <= LEARNING.maxStrengthPerPartner);
  });

  it("resets learned personalization without touching declared answers", async () => {
    await callAs(saveRelationshipLearningAnswer, "me", {questionId: "rl_humor_importance", answerId: "a"});
    await recordLearningEvent(db, {
      actorUid: "me", otherUid: "other", type: "match", key: "m1",
      strength: SIGNAL_STRENGTHS.match, vector: HUMOR_HIGH, nowMs: T0,
    });
    assert.ok((await db.doc(personalizationProfilePath("me")).get()).exists);
    await assert.rejects(callAs(resetMyPersonalization, null), /sign-in-required/);
    const result = await callAs(resetMyPersonalization, "me");
    assert.equal(result.ok, true);
    assert.equal((await db.doc(personalizationProfilePath("me")).get()).exists, false);
    assert.equal((await db.collection("users/me/personalizationPartners").get()).size, 0);
    assert.ok((await stored("me")).answers.rl_humor_importance, "declared answers stay");
    // A replayed old event is still recognised and cannot re-teach the fresh profile.
    const replay = await recordLearningEvent(db, {
      actorUid: "me", otherUid: "other", type: "match", key: "m1",
      strength: SIGNAL_STRENGTHS.match, vector: HUMOR_HIGH, nowMs: T0 + DAY,
    });
    assert.equal(replay.outcome, "duplicate");
  });
});

describe("privacy: relationship learning never touches message content", () => {
  it("has no reference to message text or ciphertext in its sources", () => {
    const dir = path.join(__dirname, "../src/relationshipLearning");
    for (const file of fs.readdirSync(dir)) {
      const source = fs.readFileSync(path.join(dir, file), "utf8");
      assert.equal(/ciphertext|messageText|\.text\b|messages\//.test(source), false, file);
    }
  });
});

describe("first-run journey: basic profile -> humor -> learning -> done", () => {
  const {journeyStage} = model;
  const required = () => ({...model.emptyLearningState(), required: true});

  it("sends a new member to humor, then learning, then done", () => {
    assert.equal(journeyStage(required(), false), "humor");
    assert.equal(journeyStage(required(), true), "learning");
    const done = {...stateAfterInitial(), required: true};
    assert.equal(journeyStage(done, true), "done");
  });

  it("never routes an existing member anywhere", () => {
    assert.equal(journeyStage(model.emptyLearningState(), false), "done");
    const partial = answerAll(model.emptyLearningState(), catalog.initialQuestions().slice(0, 3));
    assert.equal(journeyStage(partial, false), "done");
  });

  it("a humor skip moves on and can never loop back", () => {
    const skipped = {...required(), journey: {humorSkippedAtMs: T0}};
    assert.equal(journeyStage(skipped, false), "learning");
    const reread = model.parseLearningState(JSON.parse(JSON.stringify(model.serializeLearningState(skipped))));
    assert.equal(journeyStage(reread, false), "learning");
  });

  it("the skip callable records once, and ignores members without a journey", async () => {
    await markLearningRequired(db, "me");
    let state = await callAs(getRelationshipLearningState, "me");
    assert.equal(state.journeyStage, "humor");
    await callAs(skipOnboardingHumor, "me");
    const first = (await stored("me")).journey.humorSkippedAtMs;
    assert.ok(first > 0);
    await callAs(skipOnboardingHumor, "me");
    assert.equal((await stored("me")).journey.humorSkippedAtMs, first);
    state = await callAs(getRelationshipLearningState, "me");
    assert.equal(state.journeyStage, "learning");
    await callAs(skipOnboardingHumor, "other");
    assert.equal(await stored("other"), undefined, "no state is created for an existing member");
    await assert.rejects(callAs(skipOnboardingHumor, null), /sign-in-required/);
  });

  it("a calibrated humor profile counts as the humor step done", async () => {
    await markLearningRequired(db, "me");
    await db.doc("users/me/humor/calibration").set({version: 1, completedCount: 15, complete: true});
    const state = await callAs(getRelationshipLearningState, "me");
    assert.equal(state.humorCalibrated, true);
    assert.equal(state.journeyStage, "learning");
  });
});

describe("learning dashboard overview", () => {
  const overview = require("../lib/relationshipLearning/overview.js");
  const richSignals = {
    hasRelationshipGoal: true, hasLifestyle: true, hasInterests: true, hasMusic: true, humorReady: true,
    relationshipAnswerCount: 5,
  };

  it("reports real coverage per category, starting from zero", () => {
    const cats = overview.categoryProgress(model.emptyLearningState(), model.noProfileSignals());
    assert.deepEqual(cats.map((c) => c.key), [...overview.LEARNING_CATEGORIES]);
    for (const c of cats) assert.equal(c.progress, 0);
    assert.equal(overview.overallProgress(cats), 0);
    const total = cats.reduce((sum, c) => sum + c.questions, 0);
    assert.equal(total, catalog.LEARNING_QUESTIONS.filter((q) => q.active).length, "every active question counted once");
  });

  it("moves with answers and existing profile data, never past 100%", () => {
    const state = stateAfterInitial();
    const partial = overview.categoryProgress(state, model.noProfileSignals());
    const rich = overview.categoryProgress(state, richSignals);
    for (let i = 0; i < partial.length; i++) {
      assert.ok(rich[i].progress >= partial[i].progress);
      assert.ok(rich[i].progress <= 1);
    }
    const comm = partial.find((c) => c.key === "communication");
    assert.ok(comm.questions > 0 && comm.answered > 0);
    const all = answerAll(state, catalog.progressiveQuestions(), "b");
    const full = overview.categoryProgress(all, richSignals);
    for (const c of full) assert.equal(c.progress, 1, c.key);
    assert.equal(overview.overallProgress(full), 1);
  });

  it("reads back only the member's own answers, in soft wording", () => {
    let state = model.applyAnswer(model.emptyLearningState(), "rl_texting", "c", T0).state;
    state = model.applyAnswer(state, "rl_plans", "a", T0).state; // no read-back defined
    const highlights = overview.answerHighlights(state);
    assert.deepEqual(highlights.map((h) => h.questionId), ["rl_texting"]);
    for (const [id, options] of Object.entries(overview.ANSWER_HIGHLIGHTS)) {
      assert.ok(catalog.learningQuestion(id), `highlight for unknown ${id}`);
      for (const text of Object.values(options)) {
        assert.equal(/\b(you are|always|never|asla|her zaman|kişiliğin)\b/i.test(text.tr + " " + text.en), false, text.en);
      }
    }
    assert.ok(overview.answerHighlights(stateAfterInitial()).length <= overview.MAX_HIGHLIGHTS);
  });

  it("serves the overview with the answered list for editing", async () => {
    for (const q of catalog.initialQuestions().slice(0, 4)) {
      await callAs(saveRelationshipLearningAnswer, "me", {questionId: q.id, answerId: "a"});
    }
    const state = await callAs(getRelationshipLearningState, "me");
    assert.equal(state.overview.answered.length, 4);
    assert.ok(state.overview.answered.every((q) => q.answerId && q.category && q.answeredAtMs));
    assert.ok(state.overview.overallProgress > 0 && state.overview.overallProgress < 1);
    assert.ok(state.overview.highlights.length > 0);
  });

  it("editing an answer updates its time and the declared weight", async () => {
    await callAs(saveRelationshipLearningAnswer, "me", {questionId: "rl_humor_importance", answerId: "a"});
    const before = (await stored("me")).answers.rl_humor_importance.answeredAtMs;
    await new Promise((r) => setTimeout(r, 5));
    await callAs(saveRelationshipLearningAnswer, "me", {questionId: "rl_humor_importance", answerId: "c"});
    const after = (await stored("me")).answers.rl_humor_importance;
    assert.equal(after.answerId, "c");
    assert.ok(after.answeredAtMs > before);
    const context = await loadPersonalizationContext(db, "me");
    assert.equal(context.declared.humor, DECLARED.importance.low);
    assert.equal(Object.keys((await stored("me")).answers).length, 1, "an edit is not a new answer");
  });

  it("a retired question can no longer be answered or steer anything", async () => {
    const question = catalog.learningQuestion("rl_humor_importance");
    const texting = catalog.learningQuestion("rl_texting");
    await callAs(saveRelationshipLearningAnswer, "me", {questionId: "rl_humor_importance", answerId: "a"});
    await callAs(saveRelationshipLearningAnswer, "me", {questionId: "rl_texting", answerId: "a"});
    question.active = false;
    texting.active = false;
    try {
      await assert.rejects(
        callAs(saveRelationshipLearningAnswer, "me", {questionId: "rl_humor_importance", answerId: "b"}),
        /invalid-question/,
      );
      const context = await loadPersonalizationContext(db, "me");
      assert.equal(context.declared.humor, 1, "a retired importance answer carries no weight");
      const state = model.parseLearningState(await stored("me"));
      assert.equal("rl_texting" in model.comparableAnswers(state), false);
      assert.equal(catalog.isComparableLearningAnswer("rl_texting", "a"), false);
    } finally {
      question.active = true;
      texting.active = true;
    }
  });
});
