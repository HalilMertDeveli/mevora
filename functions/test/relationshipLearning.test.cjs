const {beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

const db = createFakeFirestore();
installFirebaseAdminStubs({db});

// The callables read the server clock; tests move it explicitly.
const realNow = Date.now;
let clock = null;
Date.now = () => clock ?? realNow();

const catalog = require("../lib/relationshipLearning/catalog.js");
const {ANSWER_WRITE_LIMIT, DECLARED_IMPORTANCE, EVIDENCE} = require("../lib/relationshipLearning/config.js");
const model = require("../lib/relationshipLearning/model.js");
const schedule = require("../lib/relationshipLearning/schedule.js");
const {confidentScore, evidenceConfidence} = require("../lib/relationshipLearning/compare.js");
const {learningStatePath, markLearningRequired} = require("../lib/relationshipLearning/store.js");
const {
  getRelationshipLearningState,
  saveDailyRelationshipAnswer,
  skipOnboardingHumor,
  skipTodayRelationshipQuestions,
  updateRelationshipAnswer,
} = require("../lib/relationshipLearning/functions.js");
const {PERSONALIZATION_DIMENSIONS, LEARNING, SIGNAL_STRENGTHS} = require("../lib/personalization/config.js");
const {
  loadPersonalizationContext,
  personalizationProfilePath,
  recordLearningEvent,
} = require("../lib/personalization/store.js");
const {resetMyPersonalization} = require("../lib/personalization/functions.js");
const {relationshipScoreForPair} = require("../lib/relationshipMatch.js");
const {scoreRelationshipCompatibility} = require("../lib/relationshipCompatibility.js");
const {getMevoraPicks} = require("../lib/picks/index.js");

const HOUR = 3_600_000;
const DAY = 24 * HOUR;
// 2026-09-29 12:00 in Istanbul (UTC+3).
const T0 = Date.UTC(2026, 8, 29, 9, 0, 0);
const TODAY = "2026-09-29";
const HUMOR_HIGH = {relationship: 50, values: 50, lifestyle: 50, interests: 50, music: 50, humor: 95};

const first = (q) => q.options[0].id;
const last = (q) => q.options[q.options.length - 1].id;

/** Answers every question of `set` in the pure model. */
function answerSet(state, set, pick = first, start = T0, count = set.questions.length) {
  let current = state;
  set.questions.slice(0, count).forEach((ref, index) => {
    const question = catalog.learningQuestion(ref.id);
    const outcome = model.applyDailyAnswer(current, set, {
      questionSetId: set.questionSetId, questionId: ref.id, questionVersion: ref.version, answerId: pick(question),
    }, start + index * 1000);
    assert.equal(outcome.ok, true, `answer ${ref.id}`);
    current = outcome.state;
  });
  return current;
}

/** A state holding the given answers, as if given on `dateKey`. */
function stateWith(answers, dateKey = TODAY) {
  const state = model.emptyLearningState();
  for (const [id, answerId] of Object.entries(answers)) {
    const question = catalog.learningQuestion(id);
    state.answers[id] = {answerId, version: question.version, dateKey, answeredAtMs: T0};
  }
  return state;
}

async function seedState(uid, state) {
  await db.doc(learningStatePath(uid)).set(model.serializeLearningState(state));
}

async function stored(uid) {
  return (await db.doc(learningStatePath(uid)).get()).data();
}

/** Answers today's whole set through the callables, as the app does. */
async function answerToday(uid, pick = first) {
  const state = await callAs(getRelationshipLearningState, uid);
  const results = [];
  for (const q of state.today.questions) {
    results.push(await callAs(saveDailyRelationshipAnswer, uid, {
      questionSetId: state.today.questionSetId, questionId: q.id, questionVersion: q.version, answerId: pick(q),
    }));
  }
  return results;
}

beforeEach(() => {
  clock = T0;
  db.reset({
    "users/me": {uid: "me"},
    "users/other": {uid: "other"},
    "users/third": {uid: "third"},
    "profiles/me": {relationshipGoal: "longTerm", interests: ["a", "b", "c"]},
    "profiles/other": {relationshipGoal: "longTerm", interests: ["a", "b", "c"]},
    "profiles/third": {relationshipGoal: "longTerm", interests: ["a", "b", "c"]},
  });
});

describe("question bank", () => {
  it("gives every question a stable unique versioned id, stable option ids and both languages", () => {
    const ids = new Set();
    for (const question of catalog.LEARNING_QUESTIONS) {
      assert.match(question.id, catalog.LEARNING_QUESTION_ID_PATTERN);
      assert.ok(question.id.endsWith(`_v${question.version}`), question.id);
      assert.ok(!ids.has(question.id), `duplicate ${question.id}`);
      ids.add(question.id);
      const optionIds = question.options.map((o) => o.id);
      assert.ok(optionIds.length >= 2);
      assert.equal(new Set(optionIds).size, optionIds.length, `duplicate option in ${question.id}`);
      for (const id of optionIds) assert.match(id, /^[a-z][a-z0-9_]{1,40}$/);
      for (const text of [question.prompt, ...question.options.map((o) => o.label)]) {
        assert.ok(text.tr.trim().length > 0 && text.en.trim().length > 0);
        assert.ok(text.tr.length <= 70 && text.en.length <= 80, `too long: ${text.en}`);
      }
      assert.ok(PERSONALIZATION_DIMENSIONS.includes(question.dimension));
      if (catalog.isImportanceQuestion(question)) {
        assert.equal(question.comparison, "none");
        assert.deepEqual(question.options.map((o) => o.value), [1, 2, 3, 4, 5]);
      } else {
        assert.ok(["exact", "distance", "matrix"].includes(question.comparison), question.id);
      }
    }
  });

  it("is large enough for a daily rotation and covers every area", () => {
    const eligible = catalog.dailyEligibleQuestions();
    assert.ok(eligible.length >= 60, `${eligible.length} questions`);
    for (const category of ["relationship", "communication", "lifestyle", "values", "humor", "music", "interests"]) {
      assert.ok(eligible.some((q) => q.category === category), `${category} missing`);
    }
    for (const dimension of PERSONALIZATION_DIMENSIONS) {
      assert.ok(eligible.some((q) => catalog.isImportanceQuestion(q) && q.dimension === dimension),
        `no importance question for ${dimension}`);
    }
  });

  it("stays away from diagnosis and sensitive traits", () => {
    const banned = /(attachment|anxious|avoidant|diagnos|disorder|depress|therapy|religio|politic|sexual|health|bağlanma|kaygı|terapi|\bdin\b|siyas|cinsel|sağlık)/i;
    for (const question of catalog.LEARNING_QUESTIONS) {
      const texts = [question.prompt, ...question.options.map((o) => o.label)].flatMap((t) => [t.tr, t.en]);
      for (const text of texts) assert.equal(banned.test(text), false, `sensitive wording: ${text}`);
    }
  });

  it("validates answers against the bank only", () => {
    assert.equal(catalog.isValidLearningAnswer("relationship_daily_contact_v1", "often"), true);
    assert.equal(catalog.isValidLearningAnswer("relationship_daily_contact_v1", "a"), false);
    assert.equal(catalog.isValidLearningAnswer("relationship_daily_contact_v2", "often"), false);
    assert.equal(catalog.isValidLearningAnswer("rl_pace", "a"), false, "the retired bank is gone");
    assert.equal(catalog.isValidLearningAnswer("rq_001", "a"), false);
    assert.equal(catalog.isValidLearningAnswer({}, "often"), false);
  });

  it("compares each question by its own rule", () => {
    // distance: rarely / few_times / often / all_day
    assert.equal(catalog.answerAgreement("relationship_daily_contact_v1", "often", "often"), 1);
    assert.equal(catalog.answerAgreement("relationship_daily_contact_v1", "rarely", "all_day"), 0);
    assert.ok(Math.abs(catalog.answerAgreement("relationship_daily_contact_v1", "few_times", "often") - 2 / 3) < 1e-9);
    // exact
    assert.equal(catalog.answerAgreement("relationship_apart_contact_v1", "voice_call", "texting"), 0);
    // matrix: "depends" sits between the two ends
    const matrix = catalog.answerAgreement("relationship_conflict_timing_v1", "talk_now", "depends");
    assert.ok(matrix > 0 && matrix < 1);
    assert.equal(
      catalog.answerAgreement("relationship_conflict_timing_v1", "talk_now", "depends"),
      catalog.answerAgreement("relationship_conflict_timing_v1", "depends", "talk_now"),
      "symmetric",
    );
    // importance answers and unknowns are never compared
    assert.equal(catalog.answerAgreement("relationship_humor_importance_v1", "important", "important"), null);
    assert.equal(catalog.answerAgreement("relationship_daily_contact_v1", "often", "nope"), null);
    assert.equal(catalog.answerAgreement("rq_001", "a", "a"), null);
  });
});

describe("global daily set: same for everyone, every day", () => {
  it("is ten questions, deterministic, with no member input at all", () => {
    const a = schedule.buildDailySet(TODAY);
    const b = schedule.buildDailySet(TODAY);
    assert.deepEqual(a, b);
    assert.equal(a.questions.length, 10);
    assert.equal(new Set(a.questions.map((q) => q.id)).size, 10);
    assert.equal(a.questionSetId, "daily-2026-09-29-s1");
    assert.equal(schedule.buildDailySet.length, 1, "the day is the only input");
  });

  it("uses the Istanbul day on the server clock", () => {
    assert.equal(schedule.learningDayKey(Date.UTC(2026, 8, 28, 21, 0)), TODAY, "00:00 Istanbul");
    assert.equal(schedule.learningDayKey(Date.UTC(2026, 8, 29, 20, 59)), TODAY, "23:59 Istanbul");
    assert.equal(schedule.learningDayKey(Date.UTC(2026, 8, 29, 21, 0)), "2026-09-30");
    assert.equal(schedule.nextLearningDayStartMs(T0), Date.UTC(2026, 8, 29, 21, 0));
  });

  it("brings a fresh set every day and walks the whole bank", () => {
    const seen = new Set();
    let previous = null;
    for (let day = 0; day < 40; day++) {
      const dateKey = schedule.learningDayKey(T0 + day * DAY);
      const ids = schedule.buildDailySet(dateKey).questions.map((q) => q.id);
      if (previous) assert.equal(ids.some((id) => previous.includes(id)), false, `${dateKey} repeats yesterday`);
      previous = ids;
      ids.forEach((id) => seen.add(id));
    }
    assert.equal(seen.size, catalog.dailyEligibleQuestions().length);
  });

  it("rejects a tampered stored set instead of trusting it", () => {
    const set = schedule.buildDailySet(TODAY);
    assert.deepEqual(schedule.parseDailySet(JSON.parse(JSON.stringify(set)), TODAY), set);
    assert.equal(schedule.parseDailySet(set, "2026-09-30"), null, "another day");
    assert.equal(schedule.parseDailySet({...set, questions: set.questions.slice(0, 9)}, TODAY), null);
    assert.equal(schedule.parseDailySet({...set, questions: [...set.questions.slice(0, 9), set.questions[0]]}, TODAY), null);
    const wrongVersion = set.questions.map((q, i) => (i === 0 ? {...q, version: 9} : q));
    assert.equal(schedule.parseDailySet({...set, questions: wrongVersion}, TODAY), null);
    const unknown = set.questions.map((q, i) => (i === 0 ? {id: "relationship_evil_v1", version: 1} : q));
    assert.equal(schedule.parseDailySet({...set, questions: unknown}, TODAY), null);
  });

  it("serves three members the identical set: ids, versions, order and options", async () => {
    const payloads = [];
    for (const [uid, at] of [["me", T0], ["other", T0 + 5 * HOUR], ["third", T0 - 8 * HOUR]]) {
      clock = at;
      const state = await callAs(getRelationshipLearningState, uid);
      payloads.push({
        questionSetId: state.today.questionSetId,
        questions: state.today.questions.map(({id, version, options, prompt}) => ({id, version, options, prompt})),
      });
    }
    assert.equal(payloads[0].questions.length, 10);
    assert.deepEqual(payloads[1], payloads[0]);
    assert.deepEqual(payloads[2], payloads[0]);
    const doc = (await db.doc(`relationshipDailySets/${TODAY}`).get()).data();
    assert.deepEqual(doc.questions.map((q) => q.id), payloads[0].questions.map((q) => q.id));
  });

  it("keeps the stored set for the whole day, even if the bank's rotation changes", async () => {
    const other = schedule.buildDailySet("2026-10-15");
    await db.doc(`relationshipDailySets/${TODAY}`).set({...other, dateKey: TODAY, questionSetId: `daily-${TODAY}-s1`});
    const state = await callAs(getRelationshipLearningState, "me");
    assert.deepEqual(state.today.questions.map((q) => q.id), other.questions.map((q) => q.id));
  });

  it("replaces a corrupt stored set with the scheduled one", async () => {
    await db.doc(`relationshipDailySets/${TODAY}`).set({dateKey: TODAY, questions: [{id: "x", version: 1}]});
    const state = await callAs(getRelationshipLearningState, "me");
    assert.deepEqual(state.today.questions.map((q) => q.id), schedule.buildDailySet(TODAY).questions.map((q) => q.id));
  });

  it("brings the next day's set after midnight Istanbul", async () => {
    clock = Date.UTC(2026, 8, 29, 20, 59);
    const late = await callAs(getRelationshipLearningState, "me");
    clock = Date.UTC(2026, 8, 29, 21, 1);
    const next = await callAs(getRelationshipLearningState, "me");
    assert.equal(late.today.dateKey, TODAY);
    assert.equal(next.today.dateKey, "2026-09-30");
    assert.notDeepEqual(next.today.questions.map((q) => q.id), late.today.questions.map((q) => q.id));
  });

  it("has no scheduler anywhere in relationship learning", () => {
    const dir = path.join(__dirname, "../src/relationshipLearning");
    for (const file of fs.readdirSync(dir)) {
      const source = fs.readFileSync(path.join(dir, file), "utf8");
      assert.equal(/onSchedule|pubsub\.schedule|every \d+ (minutes|hours)/.test(source), false, file);
    }
  });
});

describe("answering today's set: progress, resume and idempotency", () => {
  const set = schedule.buildDailySet(TODAY);

  it("counts progress per answer so a restart resumes where it stopped", () => {
    const four = answerSet(model.emptyLearningState(), set, first, T0, 4);
    const reread = model.parseLearningState(JSON.parse(JSON.stringify(model.serializeLearningState(four))));
    assert.equal(model.answeredToday(reread, set).length, 4);
    assert.equal(model.isDayCompleted(reread, TODAY), false);
    const firstOpen = set.questions.findIndex((q) => !model.answeredToday(reread, set).includes(q.id));
    assert.equal(firstOpen, 4, "resumes at question 5");
  });

  it("completes exactly once, and a repeated or changed answer never double counts", () => {
    let state = answerSet(model.emptyLearningState(), set, first, T0, 9);
    const lastRef = set.questions[9];
    const lastQuestion = catalog.learningQuestion(lastRef.id);
    const input = {questionSetId: set.questionSetId, questionId: lastRef.id, questionVersion: lastRef.version};
    const done = model.applyDailyAnswer(state, set, {...input, answerId: first(lastQuestion)}, T0 + 99);
    assert.equal(done.completedTodayNow, true);
    assert.equal(done.firstSetCompletedNow, true);
    state = done.state;
    assert.equal(state.completedDays, 1);
    const replay = model.applyDailyAnswer(state, set, {...input, answerId: first(lastQuestion)}, T0 + 500);
    assert.equal(replay.changed, false);
    assert.equal(replay.completedTodayNow, false);
    const changedMind = model.applyDailyAnswer(state, set, {...input, answerId: last(lastQuestion)}, T0 + 600);
    assert.equal(changedMind.changed, true);
    assert.equal(changedMind.completedTodayNow, false);
    assert.equal(changedMind.state.completedDays, 1);
    assert.equal(changedMind.state.answerCounts["2026-09"], 10, "a changed answer is not a new one");
    assert.equal(Object.keys(changedMind.state.answers).length, 10);
  });

  it("rejects anything outside today's server set", () => {
    const state = model.emptyLearningState();
    const ref = set.questions[0];
    const question = catalog.learningQuestion(ref.id);
    const ok = {questionSetId: set.questionSetId, questionId: ref.id, questionVersion: ref.version, answerId: first(question)};
    const reason = (input) => model.applyDailyAnswer(state, set, input, T0).reason;
    assert.equal(reason({...ok, questionSetId: "daily-2026-09-28-s1"}), "stale-set", "yesterday");
    assert.equal(reason({...ok, questionSetId: "daily-2026-09-30-s1"}), "stale-set", "tomorrow");
    assert.equal(reason({...ok, questionSetId: "mine"}), "stale-set");
    const outside = catalog.dailyEligibleQuestions().find((q) => !set.questions.some((r) => r.id === q.id));
    assert.equal(reason({...ok, questionId: outside.id, answerId: first(outside)}), "not-in-set");
    assert.equal(reason({...ok, questionVersion: 2}), "wrong-version");
    assert.equal(reason({...ok, questionVersion: "1"}), "wrong-version");
    assert.equal(reason({...ok, answerId: "z"}), "invalid-answer");
    assert.equal(reason({...ok, answerId: {$gt: ""}}), "invalid-answer");
    assert.equal(model.applyDailyAnswer(state, set, ok, T0).ok, true);
  });

  it("drops tampered and retired stored answers instead of trusting them", () => {
    const parsed = model.parseLearningState({
      required: true,
      answers: {
        rl_pace: {answerId: "a", version: 1, answeredAtMs: 1},
        relationship_daily_contact_v1: {answerId: "often", version: 1, dateKey: TODAY, answeredAtMs: 1},
        relationship_pace_v1: {answerId: "fast", version: 1},
        relationship_late_reply_v1: {answerId: "zzz", version: 1, dateKey: TODAY},
      },
      initialCompletedAtMs: "soon",
      answerCounts: {"2026-09": 3, bad: 9},
    });
    assert.deepEqual(Object.keys(parsed.answers), ["relationship_daily_contact_v1"]);
    assert.equal(parsed.initialCompletedAtMs, null);
    assert.deepEqual(parsed.answerCounts, {"2026-09": 3});
  });

  it("bounds how many answers one member can write in a window", () => {
    const ref = set.questions[0];
    const question = catalog.learningQuestion(ref.id);
    const input = (answerId) => ({questionSetId: set.questionSetId, questionId: ref.id, questionVersion: ref.version, answerId});
    let state = model.emptyLearningState();
    for (let i = 0; i < ANSWER_WRITE_LIMIT.max; i++) {
      const outcome = model.applyDailyAnswer(state, set, input(i % 2 ? first(question) : last(question)), T0 + i);
      assert.equal(outcome.ok, true);
      state = outcome.state;
    }
    const other = question.options[1].id;
    assert.deepEqual(model.applyDailyAnswer(state, set, input(other), T0 + 1000), {ok: false, reason: "rate-limited"});
    assert.equal(model.applyDailyAnswer(state, set, input(other), T0 + ANSWER_WRITE_LIMIT.windowMs + 1).ok, true);
  });

  it("accumulates answers across days; each day counts only its own", () => {
    let state = answerSet(model.emptyLearningState(), set);
    const tomorrow = schedule.buildDailySet("2026-09-30");
    assert.equal(model.answeredToday(state, tomorrow).length, 0);
    assert.equal(model.isDayCompleted(state, "2026-09-30"), false);
    state = answerSet(state, tomorrow, first, T0 + DAY);
    assert.equal(Object.keys(state.answers).length, 20, "yesterday's answers are kept");
    assert.equal(state.completedDays, 2);
    assert.equal(state.answerCounts["2026-09"], 20);
    assert.equal(state.initialCompletedAtMs, T0 + 9000, "the first set stays the first");
  });

  it("lets existing members skip a day, but not a new member's first set", () => {
    const existing = model.skipToday(model.emptyLearningState(), set, T0);
    assert.equal(existing.ok, true);
    assert.equal(model.isDaySkipped(existing.state, TODAY), true);
    assert.equal(model.isDaySkipped(existing.state, "2026-09-30"), false, "tomorrow comes back");
    const fresh = {...model.emptyLearningState(), required: true};
    assert.deepEqual(model.skipToday(fresh, set, T0), {ok: false, reason: "first-set-required"});
    const onboarded = answerSet(fresh, set);
    assert.equal(model.skipToday(onboarded, schedule.buildDailySet("2026-09-30"), T0 + DAY).ok, true);
  });

  it("blocks Picks only for new members before their first set", () => {
    assert.equal(model.isLearningBlockingPicks(model.emptyLearningState()), false, "existing members never");
    const fresh = {...model.emptyLearningState(), required: true};
    assert.equal(model.isLearningBlockingPicks(fresh), true);
    assert.equal(model.isLearningBlockingPicks(answerSet(fresh, set)), false);
  });
});

describe("daily relationship callables", () => {
  it("requires sign-in", async () => {
    await assert.rejects(callAs(getRelationshipLearningState, null), /sign-in-required/);
    await assert.rejects(callAs(saveDailyRelationshipAnswer, null, {}), /sign-in-required/);
    await assert.rejects(callAs(updateRelationshipAnswer, null, {}), /sign-in-required/);
    await assert.rejects(callAs(skipTodayRelationshipQuestions, null), /sign-in-required/);
  });

  it("serves today's ten in both languages, with no scoring metadata", async () => {
    const state = await callAs(getRelationshipLearningState, "me");
    assert.equal(state.today.total, 10);
    assert.equal(state.today.answered, 0);
    assert.equal(state.today.completed, false);
    const q = state.today.questions[0];
    assert.ok(q.prompt.tr && q.prompt.en && q.version >= 1 && q.category && q.answerType);
    assert.equal(q.answerId, null);
    const json = JSON.stringify(state.today);
    assert.equal(/"comparison"|"matrix"|"value"|"topic"/.test(json), false, "no scoring rules leak");
    assert.equal(state.required, false, "an existing member is never required");
    assert.equal(state.journeyStage, "daily", "an existing member sees today's set");
  });

  it("resumes after a restart on the first unanswered question", async () => {
    const before = await callAs(getRelationshipLearningState, "me");
    for (const q of before.today.questions.slice(0, 3)) {
      await callAs(saveDailyRelationshipAnswer, "me", {
        questionSetId: before.today.questionSetId, questionId: q.id, questionVersion: q.version, answerId: last(q),
      });
    }
    clock = T0 + 6 * HOUR;
    const after = await callAs(getRelationshipLearningState, "me");
    assert.equal(after.today.answered, 3);
    assert.deepEqual(after.today.questions.slice(0, 3).map((q) => q.answerId), before.today.questions.slice(0, 3).map(last));
    assert.equal(after.today.questions.findIndex((q) => q.answerId === null), 3);
  });

  it("writes only to the caller's own state, whatever the payload claims", async () => {
    const state = await callAs(getRelationshipLearningState, "me");
    const q = state.today.questions[0];
    await callAs(saveDailyRelationshipAnswer, "me", {
      questionSetId: state.today.questionSetId, questionId: q.id, questionVersion: q.version, answerId: first(q),
      uid: "other", userId: "other", dateKey: "2026-01-01",
    });
    assert.equal((await stored("me")).answers[q.id].dateKey, TODAY, "the day is the server's");
    assert.equal(await stored("other"), undefined);
  });

  it("rejects forged or stale payloads and never stores them", async () => {
    const state = await callAs(getRelationshipLearningState, "me");
    const q = state.today.questions[0];
    const ok = {questionSetId: state.today.questionSetId, questionId: q.id, questionVersion: q.version, answerId: first(q)};
    const outside = catalog.dailyEligibleQuestions().find((c) => !state.today.questions.some((t) => t.id === c.id));
    for (const payload of [
      {...ok, questionSetId: "daily-2026-09-28-s1"},
      {...ok, questionSetId: "daily-2026-09-30-s1"},
      {...ok, questionSetId: undefined},
      {...ok, questionId: outside.id, answerId: first(outside)},
      {...ok, questionVersion: 2},
      {...ok, answerId: "z"},
      {...ok, questionId: "../users/other"},
      {...ok, questionId: "rl_pace", answerId: "a"},
      {},
    ]) {
      await assert.rejects(callAs(saveDailyRelationshipAnswer, "me", payload), /invalid|stale|not-in-set|wrong-version/);
    }
    assert.equal(await stored("me"), undefined);
  });

  it("completes the day once, survives retries, and records the completion once", async () => {
    const state = await callAs(getRelationshipLearningState, "me");
    let completions = 0;
    for (const q of state.today.questions) {
      for (let attempt = 0; attempt < 2; attempt++) {
        const result = await callAs(saveDailyRelationshipAnswer, "me", {
          questionSetId: state.today.questionSetId, questionId: q.id, questionVersion: q.version, answerId: first(q),
        });
        if (result.completedTodayNow) completions += 1;
      }
    }
    assert.equal(completions, 1);
    const after = await callAs(getRelationshipLearningState, "me");
    assert.equal(after.today.completed, true);
    assert.equal(after.today.answered, 10);
    assert.equal(after.journeyStage, "done", "the set is not shown again today");
    const record = (await db.doc(`users/me/relationshipDaily/${TODAY}`).get()).data();
    assert.equal(record.questionSetId, state.today.questionSetId);
    assert.equal((await db.collection("users/me/relationshipDaily").get()).size, 1);
    assert.equal((await stored("me")).completedDays, 1);
  });

  it("brings a new set the next day, keeps yesterday's answers, and refuses yesterday's set", async () => {
    await answerToday("me");
    const yesterday = await callAs(getRelationshipLearningState, "me");
    clock = T0 + DAY;
    const today = await callAs(getRelationshipLearningState, "me");
    assert.equal(today.today.dateKey, "2026-09-30");
    assert.equal(today.today.answered, 0);
    assert.equal(today.journeyStage, "daily");
    const old = yesterday.today.questions[0];
    await assert.rejects(callAs(saveDailyRelationshipAnswer, "me", {
      questionSetId: yesterday.today.questionSetId, questionId: old.id, questionVersion: old.version, answerId: last(old),
    }), /stale-set/);
    await answerToday("me");
    const stateNow = await stored("me");
    assert.equal(Object.keys(stateNow.answers).length, 20);
    assert.equal(stateNow.completedDays, 2);
    assert.equal((await db.collection("users/me/relationshipDaily").get()).size, 2);
  });

  it("skips today for an existing member, and refuses a new member's first set", async () => {
    const skipped = await callAs(skipTodayRelationshipQuestions, "me");
    assert.equal(skipped.today.skipped, true);
    assert.equal((await callAs(getRelationshipLearningState, "me")).journeyStage, "done");
    clock = T0 + DAY;
    assert.equal((await callAs(getRelationshipLearningState, "me")).journeyStage, "daily", "tomorrow comes back");
    await markLearningRequired(db, "other");
    await assert.rejects(callAs(skipTodayRelationshipQuestions, "other"), /first-set-required/);
  });

  it("marks new members as required, create-only, never overwriting progress", async () => {
    await markLearningRequired(db, "newbie");
    assert.equal((await stored("newbie")).required, true);
    await answerToday("me");
    await markLearningRequired(db, "me");
    const mine = await stored("me");
    assert.equal(mine.required, false);
    assert.equal(Object.keys(mine.answers).length, 10);
  });

  it("holds a new member's Picks until their first set, never an existing member's", async () => {
    const existing = await callAs(getMevoraPicks, "other");
    assert.notEqual(existing.emptyReason, "learningRequired");
    assert.equal(existing.learning.today.dateKey, TODAY);
    await markLearningRequired(db, "me");
    const blocked = await callAs(getMevoraPicks, "me");
    assert.equal(blocked.status, "empty");
    assert.equal(blocked.emptyReason, "learningRequired");
    assert.equal(blocked.learning.blocksPicks, true);
    await answerToday("me");
    const open = await callAs(getMevoraPicks, "me");
    assert.notEqual(open.emptyReason, "learningRequired");
    assert.equal(open.learning.firstSetCompleted, true);
    assert.equal(open.learning.today.completed, true);
  });
});

describe("compatibility from daily answers", () => {
  it("mirrors comparable answers only, never importance answers", async () => {
    await seedState("me", stateWith({relationship_humor_importance_v1: "very_important"}));
    await answerToday("me");
    const summary = (await db.doc("users/me/relationshipMatch/summary").get()).data();
    const mirrored = Object.keys(summary.learningAnswers);
    assert.equal(mirrored.length, 10);
    assert.equal(mirrored.includes("relationship_humor_importance_v1"), false);
  });

  it("scores same-minded members above opposite ones, from the same questions", async () => {
    await answerToday("me", first);
    await answerToday("other", first);
    await answerToday("third", last);
    const alike = await relationshipScoreForPair("me", "other");
    assert.equal(alike.sharedQuestionCount, 10);
    assert.equal(alike.alignedCount, 10);
    assert.equal(alike.score, confidentScore(100, 10));
    assert.ok(alike.topTopics.length > 0);
    const apart = scoreRelationshipCompatibility(
      (await db.doc("users/me/relationshipMatch/summary").get()).data().learningAnswers,
      (await db.doc("users/third/relationshipMatch/summary").get()).data().learningAnswers,
    );
    assert.equal(apart.sharedQuestionCount, 10);
    assert.ok(apart.score < alike.score);
    assert.ok(apart.score <= 50);
  });

  it("gives partial credit to close answers on distance questions", () => {
    const close = scoreRelationshipCompatibility(
      {relationship_daily_contact_v1: "few_times"}, {relationship_daily_contact_v1: "often"});
    const far = scoreRelationshipCompatibility(
      {relationship_daily_contact_v1: "rarely"}, {relationship_daily_contact_v1: "all_day"});
    assert.ok(close.score > far.score);
    assert.equal(close.alignedCount, 0, "2/3 agreement is not an aligned view");
    assert.ok(EVIDENCE.alignedAtLeast > 2 / 3);
  });

  it("grows confidence as shared answers accumulate across days", async () => {
    await answerToday("me");
    await answerToday("other");
    const dayOne = await relationshipScoreForPair("me", "other");
    clock = T0 + DAY;
    await answerToday("me");
    await answerToday("other");
    const dayTwo = await relationshipScoreForPair("me", "other");
    assert.equal(dayTwo.sharedQuestionCount, 20);
    assert.ok(dayTwo.score > dayOne.score, `${dayTwo.score} > ${dayOne.score}`);
    assert.ok(evidenceConfidence(200) > evidenceConfidence(20));
    assert.equal(confidentScore(100, 0), 50);
  });

  it("never compares different versions or questions only one member answered", () => {
    const result = scoreRelationshipCompatibility(
      {relationship_daily_contact_v1: "often", relationship_pace_v1: "fast"},
      {relationship_daily_contact_v2: "often", relationship_tidiness_v1: "very_tidy"},
    );
    assert.equal(result.sharedQuestionCount, 0);
  });
});

describe("declared + observed personalization", () => {
  it("follows importance answers only, inside the band", () => {
    const neutral = model.declaredAdjustments(model.emptyLearningState());
    for (const d of PERSONALIZATION_DIMENSIONS) assert.equal(neutral[d], 1);
    const declared = model.declaredAdjustments(stateWith({
      relationship_humor_importance_v1: "very_important",
      relationship_music_importance_v1: "not_important",
      relationship_daily_contact_v1: "often",
    }));
    assert.equal(declared.humor, DECLARED_IMPORTANCE[5]);
    assert.equal(declared.music, DECLARED_IMPORTANCE[1]);
    assert.equal(declared.values, 1);
    for (const d of PERSONALIZATION_DIMENSIONS) assert.ok(declared[d] >= 0.7 && declared[d] <= 1.3);
  });

  it("applies declared weights even with interaction learning OFF, and observed ones only when ON", async () => {
    await seedState("me", stateWith({relationship_humor_importance_v1: "very_important"}));
    await db.doc(personalizationProfilePath("me")).set({
      algorithmVersion: 1,
      partnerCount: LEARNING.minDistinctPartners,
      dimensions: {music: {adjustment: 1.2, evidence: 10, positive: 10, negative: 0}},
      eventCount: 10,
      updatedAtMs: T0,
    });
    const on = await loadPersonalizationContext(db, "me");
    assert.equal(on.declared.humor, DECLARED_IMPORTANCE[5]);
    assert.equal(on.observed.music, 1.2);
    await db.doc("userSettings/me").set({personalizeRecommendations: false});
    const off = await loadPersonalizationContext(db, "me");
    assert.equal(off.observed.music, 1);
    assert.equal(off.adjustments.music, 1);
    assert.equal(off.adjustments.humor, DECLARED_IMPORTANCE[5], "the member's own answers still count");
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
    const partners = await db.collection("users/me/personalizationPartners").get();
    assert.equal(partners.size, 1);
    assert.equal(partners.docs[0].id.includes("other"), false, "partner ids are hashed");
    assert.ok(partners.docs[0].data().strengthSpent <= LEARNING.maxStrengthPerPartner);
  });

  it("resets learned personalization without touching the member's answers", async () => {
    await seedState("me", stateWith({relationship_humor_importance_v1: "very_important"}));
    await recordLearningEvent(db, {
      actorUid: "me", otherUid: "other", type: "match", key: "m1",
      strength: SIGNAL_STRENGTHS.match, vector: HUMOR_HIGH, nowMs: T0,
    });
    assert.ok((await db.doc(personalizationProfilePath("me")).get()).exists);
    const result = await callAs(resetMyPersonalization, "me");
    assert.equal(result.ok, true);
    assert.equal((await db.doc(personalizationProfilePath("me")).get()).exists, false);
    assert.ok((await stored("me")).answers.relationship_humor_importance_v1, "answers stay");
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

  it("never returns another member's answers", async () => {
    await answerToday("other", last);
    const mine = await callAs(getRelationshipLearningState, "me");
    assert.ok(mine.today.questions.every((q) => q.answerId === null));
    assert.deepEqual(mine.overview.answered, []);
  });
});

describe("journey: basic profile -> humor -> today's questions -> done", () => {
  const {journeyStage} = model;
  const required = () => ({...model.emptyLearningState(), required: true});

  it("sends a new member to humor, then today's set, then done", () => {
    assert.equal(journeyStage(required(), false, TODAY), "humor");
    assert.equal(journeyStage(required(), true, TODAY), "daily");
    const done = answerSet(required(), schedule.buildDailySet(TODAY));
    assert.equal(journeyStage(done, true, TODAY), "done");
    assert.equal(journeyStage(done, true, "2026-09-30"), "daily", "a new day brings a new set");
  });

  it("never sends an existing member to humor", () => {
    assert.equal(journeyStage(model.emptyLearningState(), false, TODAY), "daily");
  });

  it("a humor skip moves on and can never loop back", () => {
    const skipped = {...required(), journey: {humorSkippedAtMs: T0}};
    assert.equal(journeyStage(skipped, false, TODAY), "daily");
    const reread = model.parseLearningState(JSON.parse(JSON.stringify(model.serializeLearningState(skipped))));
    assert.equal(journeyStage(reread, false, TODAY), "daily");
  });

  it("the humor skip callable records once, and ignores members without a journey", async () => {
    await markLearningRequired(db, "me");
    let state = await callAs(getRelationshipLearningState, "me");
    assert.equal(state.journeyStage, "humor");
    await callAs(skipOnboardingHumor, "me");
    const firstSkip = (await stored("me")).journey.humorSkippedAtMs;
    assert.ok(firstSkip > 0);
    await callAs(skipOnboardingHumor, "me");
    assert.equal((await stored("me")).journey.humorSkippedAtMs, firstSkip);
    state = await callAs(getRelationshipLearningState, "me");
    assert.equal(state.journeyStage, "daily");
    await callAs(skipOnboardingHumor, "other");
    assert.equal(await stored("other"), undefined, "no state is created for an existing member");
  });

  it("a calibrated humor profile counts as the humor step done", async () => {
    await markLearningRequired(db, "me");
    await db.doc("users/me/humor/calibration").set({version: 1, completedCount: 15, complete: true});
    const state = await callAs(getRelationshipLearningState, "me");
    assert.equal(state.humorCalibrated, true);
    assert.equal(state.journeyStage, "daily");
  });
});

describe("learning dashboard", () => {
  const overview = require("../lib/relationshipLearning/overview.js");

  it("reports real coverage per category, starting from zero", () => {
    const cats = overview.categoryProgress(model.emptyLearningState(), model.noProfileSignals());
    assert.deepEqual(cats.map((c) => c.key), [...overview.LEARNING_CATEGORIES]);
    for (const c of cats) assert.equal(c.progress, 0);
    const total = cats.reduce((sum, c) => sum + c.questions, 0);
    assert.equal(total, catalog.LEARNING_QUESTIONS.filter((q) => q.active).length, "every active question counted once");
  });

  it("reads back only the member's own answers, in soft wording", () => {
    const highlights = overview.answerHighlights(stateWith({
      relationship_daily_contact_v1: "all_day",
      relationship_apart_contact_v1: "texting", // no read-back defined
    }));
    assert.deepEqual(highlights.map((h) => h.questionId), ["relationship_daily_contact_v1"]);
    for (const [id, options] of Object.entries(overview.ANSWER_HIGHLIGHTS)) {
      const question = catalog.learningQuestion(id);
      assert.ok(question, `highlight for unknown ${id}`);
      for (const [optionId, text] of Object.entries(options)) {
        assert.ok(question.options.some((o) => o.id === optionId), `${id}: unknown option ${optionId}`);
        assert.equal(/\b(you are|always|never|asla|her zaman|kişiliğin)\b/i.test(text.tr + " " + text.en), false, text.en);
      }
    }
  });

  it("serves real totals and the answered list for editing", async () => {
    await answerToday("me");
    clock = T0 + DAY;
    const state = await callAs(getRelationshipLearningState, "me");
    assert.deepEqual(state.overview.totals, {thisMonth: 10, total: 10, completedDays: 1});
    assert.equal(state.overview.answered.length, 10);
    assert.ok(state.overview.answered.every((q) => q.answerId && q.category && q.answeredAtMs && q.version));
    clock = Date.UTC(2026, 9, 1, 9, 0);
    const october = await callAs(getRelationshipLearningState, "me");
    assert.deepEqual(october.overview.totals, {thisMonth: 0, total: 10, completedDays: 1});
  });

  it("edits an earlier answer without counting it again, and never answers anything new", async () => {
    await seedState("me", stateWith({relationship_humor_importance_v1: "very_important"}, "2026-09-20"));
    const payload = {questionId: "relationship_humor_importance_v1", questionVersion: 1};
    await callAs(updateRelationshipAnswer, "me", {...payload, answerId: "not_important"});
    const after = (await stored("me")).answers.relationship_humor_importance_v1;
    assert.equal(after.answerId, "not_important");
    assert.equal(after.dateKey, "2026-09-20", "keeps the day it was given for");
    assert.equal((await loadPersonalizationContext(db, "me")).declared.humor, DECLARED_IMPORTANCE[1]);
    assert.equal((await stored("me")).answerCounts["2026-09"], undefined, "an edit is not a new answer");
    await assert.rejects(callAs(updateRelationshipAnswer, "me",
      {questionId: "relationship_daily_contact_v1", questionVersion: 1, answerId: "often"}), /not-answered/);
    await assert.rejects(callAs(updateRelationshipAnswer, "me", {...payload, answerId: "z"}), /invalid-answer/);
    await assert.rejects(callAs(updateRelationshipAnswer, "me", {...payload, questionVersion: 2, answerId: "important"}),
      /wrong-version/);
    await assert.rejects(callAs(updateRelationshipAnswer, "other", {...payload, answerId: "important"}), /not-answered/);
  });

  it("a retired question can no longer be compared or steer anything", async () => {
    const importance = catalog.learningQuestion("relationship_humor_importance_v1");
    const contact = catalog.learningQuestion("relationship_daily_contact_v1");
    await seedState("me", stateWith({
      relationship_humor_importance_v1: "very_important",
      relationship_daily_contact_v1: "often",
    }));
    importance.active = false;
    contact.active = false;
    try {
      assert.equal((await loadPersonalizationContext(db, "me")).declared.humor, 1);
      const state = model.parseLearningState(await stored("me"));
      assert.equal("relationship_daily_contact_v1" in model.comparableAnswers(state), false);
      assert.equal(catalog.isComparableLearningAnswer("relationship_daily_contact_v1", "often"), false);
      await assert.rejects(callAs(updateRelationshipAnswer, "me",
        {questionId: "relationship_daily_contact_v1", questionVersion: 1, answerId: "rarely"}), /not-answered/);
    } finally {
      importance.active = true;
      contact.active = true;
    }
  });
});
