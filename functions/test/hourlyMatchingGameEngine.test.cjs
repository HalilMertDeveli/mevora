const test = require("node:test");
const assert = require("node:assert/strict");
const {
  answerOrdinal,
  questionSimilarity,
  scoreAnswerSnapshots,
  optimizeMatches,
  comparePairScores,
  istanbulRoundId,
  previousIstanbulRoundId,
  parseRoundId,
  predecessorRoundId,
} = require("../lib/hourlyMatchingGameEngine.js");

test("ordinal maps a/b/c", () => {
  assert.equal(answerOrdinal("a"), 0);
  assert.equal(answerOrdinal("B"), 1);
  assert.equal(answerOrdinal("c"), 2);
  assert.equal(answerOrdinal("x"), null);
});

test("similarity exact and distance", () => {
  assert.equal(questionSimilarity("a", "a"), 1);
  assert.equal(questionSimilarity("a", "b"), 0.5);
  assert.equal(questionSimilarity("a", "c"), 0);
});

test("identical answer maps score 100", () => {
  const answers = {rq_001: "a", rq_002: "b", rq_003: "c"};
  const scored = scoreAnswerSnapshots(answers, {...answers});
  assert.equal(scored.score, 100);
  assert.equal(scored.exactAligned, 3);
});

test("optimizeMatches pairs two identical users", () => {
  const answers = {rq_001: "a", rq_002: "a", rq_003: "a"};
  const pairs = optimizeMatches({
    participants: [
      {uid: "u1", answers},
      {uid: "u2", answers},
      {uid: "u3", answers: {rq_001: "c", rq_002: "c", rq_003: "c"}},
    ],
  });
  assert.equal(pairs.length, 1);
  assert.deepEqual([pairs[0].userA, pairs[0].userB].sort(), ["u1", "u2"]);
  assert.equal(pairs[0].score, 100);
});

test("optimizeMatches is 1:1 and deterministic", () => {
  const a = {rq_001: "a", rq_002: "a", rq_003: "a"};
  const b = {rq_001: "a", rq_002: "a", rq_003: "b"};
  const c = {rq_001: "a", rq_002: "b", rq_003: "c"};
  const d = {rq_001: "c", rq_002: "c", rq_003: "c"};
  const first = optimizeMatches({
    participants: [
      {uid: "a", answers: a},
      {uid: "b", answers: b},
      {uid: "c", answers: c},
      {uid: "d", answers: d},
    ],
  });
  const second = optimizeMatches({
    participants: [
      {uid: "d", answers: d},
      {uid: "c", answers: c},
      {uid: "b", answers: b},
      {uid: "a", answers: a},
    ],
  });
  assert.equal(first.length, 2);
  assert.deepEqual(
    first.map((p) => `${p.userA}|${p.userB}`).sort(),
    second.map((p) => `${p.userA}|${p.userB}`).sort(),
  );
  const used = new Set();
  for (const p of first) {
    assert.equal(used.has(p.userA), false);
    assert.equal(used.has(p.userB), false);
    used.add(p.userA);
    used.add(p.userB);
  }
});

test("single participant yields no match", () => {
  const pairs = optimizeMatches({
    participants: [{uid: "solo", answers: {rq_001: "a", rq_002: "b", rq_003: "c"}}],
  });
  assert.equal(pairs.length, 0);
});

test("comparePairScores prefers exact aligned", () => {
  const left = {
    userA: "a",
    userB: "b",
    score: 90,
    exactAligned: 3,
    shared: 3,
    avgDistance: 0,
  };
  const right = {
    userA: "a",
    userB: "c",
    score: 100,
    exactAligned: 2,
    shared: 3,
    avgDistance: 0.3,
  };
  assert.ok(comparePairScores(left, right) < 0);
});

test("istanbulRoundId format and previous hour", () => {
  // Fixed UTC instant: 2026-08-27 10:30 UTC = 13:30 Istanbul (UTC+3 in Aug)
  const now = new Date("2026-08-27T10:30:00.000Z");
  const id = istanbulRoundId(now);
  assert.match(id, /^\d{10}$/);
  assert.equal(id.slice(0, 8), "20260827");
  assert.equal(id.slice(8), "13");
  const prev = previousIstanbulRoundId(now);
  assert.equal(prev, "2026082712");
  const parsed = parseRoundId(id);
  assert.deepEqual(parsed, {year: 2026, month: 8, day: 27, hour: 13});
});

test("day wrap 23 -> 00 Istanbul", () => {
  // 2026-08-27 20:30 UTC = 2026-08-27 23:30 Istanbul
  const late = new Date("2026-08-27T20:30:00.000Z");
  assert.equal(istanbulRoundId(late), "2026082723");
  // 2026-08-27 21:30 UTC = 2026-08-28 00:30 Istanbul
  const next = new Date("2026-08-27T21:30:00.000Z");
  assert.equal(istanbulRoundId(next), "2026082800");
  assert.equal(previousIstanbulRoundId(next), "2026082723");
});

test("predecessorRoundId wraps midnight", () => {
  assert.equal(predecessorRoundId("2026082713"), "2026082712");
  assert.equal(predecessorRoundId("2026082800"), "2026082723");
});
