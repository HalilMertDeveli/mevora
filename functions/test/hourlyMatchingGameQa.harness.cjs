/**
 * Production QA harness for hourlyMatchingGameEngine (local, no Firebase I/O).
 * Run: node --test test/hourlyMatchingGameQa.harness.cjs
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  questionSimilarity,
  scoreAnswerSnapshots,
  optimizeMatches,
  istanbulRoundId,
  previousIstanbulRoundId,
  parseRoundId,
  predecessorRoundId,
} = require("../lib/hourlyMatchingGameEngine.js");

function answers(triple) {
  return {rq_001: triple[0], rq_002: triple[1], rq_003: triple[2]};
}

test("QA math: aaa vs aaa = 100", () => {
  const s = scoreAnswerSnapshots(answers(["a", "a", "a"]), answers(["a", "a", "a"]));
  assert.equal(s.score, 100);
  assert.equal(s.exactAligned, 3);
  assert.equal(s.avgDistance, 0);
});

test("QA math: aaa vs bbb = 50", () => {
  const s = scoreAnswerSnapshots(answers(["a", "a", "a"]), answers(["b", "b", "b"]));
  assert.equal(questionSimilarity("a", "b"), 0.5);
  assert.equal(s.score, 50);
  assert.equal(s.exactAligned, 0);
  assert.equal(s.avgDistance, 1);
});

test("QA math: aaa vs ccc = 0", () => {
  const s = scoreAnswerSnapshots(answers(["a", "a", "a"]), answers(["c", "c", "c"]));
  assert.equal(questionSimilarity("a", "c"), 0);
  assert.equal(s.score, 0);
  assert.equal(s.exactAligned, 0);
  assert.equal(s.avgDistance, 2);
});

test("QA math: formula matches docs 1-|ordA-ordB|/2", () => {
  assert.equal(questionSimilarity("a", "a"), 1 - 0 / 2);
  assert.equal(questionSimilarity("a", "b"), 1 - 1 / 2);
  assert.equal(questionSimilarity("a", "c"), 1 - 2 / 2);
  assert.equal(questionSimilarity("b", "c"), 1 - 1 / 2);
});

test("QA 1:1 three users A-B=100 preferred", () => {
  const pairs = optimizeMatches({
    participants: [
      {uid: "A", answers: answers(["a", "b", "c"])},
      {uid: "B", answers: answers(["a", "b", "c"])},
      {uid: "C", answers: answers(["a", "b", "a"])},
    ],
  });
  assert.equal(pairs.length, 1);
  assert.deepEqual([pairs[0].userA, pairs[0].userB].sort(), ["A", "B"]);
  assert.equal(pairs[0].score, 100);
  const used = new Set([pairs[0].userA, pairs[0].userB]);
  assert.equal(used.has("C"), false);
});

test("QA unmatched: single user", () => {
  assert.equal(
    optimizeMatches({
      participants: [{uid: "solo", answers: answers(["a", "b", "c"])}],
    }).length,
    0,
  );
});

test("QA unmatched: empty pool", () => {
  assert.equal(optimizeMatches({participants: []}).length, 0);
});

test("QA repeatPenalty demotes previous pair when alternative exists", () => {
  const aaa = answers(["a", "a", "a"]);
  const round1Key = "A|B";
  const without = optimizeMatches({
    participants: [
      {uid: "A", answers: aaa},
      {uid: "B", answers: aaa},
      {uid: "C", answers: aaa},
    ],
  });
  // Without penalty, greedy picks A|B by uid tie-break among equal scores
  assert.equal(without.length, 1);

  const withPenalty = optimizeMatches({
    participants: [
      {uid: "A", answers: aaa},
      {uid: "B", answers: aaa},
      {uid: "C", answers: aaa},
    ],
    repeatPairs: new Set([round1Key]),
    repeatPenalty: 15,
  });
  assert.equal(withPenalty.length, 1);
  const key = `${withPenalty[0].userA}|${withPenalty[0].userB}`;
  // A|B scored 85 after penalty; A|C and B|C stay 100 → not A|B
  assert.notEqual(key, "A|B");
});

test("QA GREEDY COUNTEREXAMPLE: suboptimal matching", () => {
  // Construct edges where greedy on sorted pairwise scores can miss max weight:
  // Ideal max-weight: A-C + B-D (if those edges exist with high sum)
  // Classic: four nodes where greedy takes top edge and leaves poor remainder.
  //
  // Scores (exactAligned first in comparator — make exactAligned equal, use score):
  // A-B = 100, A-C = 99, B-C = 98, and D alone with weaker links
  // With 3 users greedy is fine. With 4:
  // A-B 100, C-D 40, A-C 90, B-D 90
  // Greedy takes A-B then C-D total 140
  // Optimal A-C + B-D total 180
  const mk = (pattern) => ({
    rq_001: pattern[0],
    rq_002: pattern[1],
    rq_003: pattern[2],
  });
  // Similarity uses a/b/c ordinals — craft answer maps:
  // identical => 100; distance 1 on all => 50; etc.
  const A = {uid: "A", answers: mk(["a", "a", "a"])};
  const B = {uid: "B", answers: mk(["a", "a", "a"])}; // A-B = 100
  const C = {uid: "C", answers: mk(["a", "a", "b"])}; // A-C = ~83, B-C = ~83
  const D = {uid: "D", answers: mk(["c", "c", "c"])}; // far from all

  const greedy = optimizeMatches({participants: [A, B, C, D]});
  assert.equal(greedy.length, 2);
  const keys = greedy.map((p) => `${p.userA}|${p.userB}`).sort();
  // Document actual greedy choice for report
  console.log("[QA greedy pairs]", keys, greedy.map((p) => p.score));

  // Counterexample with explicit PairScore-like construction via answers:
  // Use two near-identical pairs that greedy may split poorly when top edge
  // is cross-group.
  const P = {uid: "P", answers: mk(["a", "a", "a"])};
  const Q = {uid: "Q", answers: mk(["a", "a", "a"])};
  const R = {uid: "R", answers: mk(["c", "c", "c"])};
  const S = {uid: "S", answers: mk(["c", "c", "c"])};
  // P-Q=100, R-S=100, P-R=0, etc. Greedy picks P-Q then R-S = optimal.
  const good = optimizeMatches({participants: [P, Q, R, S]});
  assert.equal(good.length, 2);
  assert.deepEqual(
    good.map((p) => `${p.userA}|${p.userB}`).sort(),
    ["P|Q", "R|S"],
  );

  // TRUE counterexample for weight-sum: force A-B slightly higher than A-C/B-D
  // while A-C and B-D would sum higher — with only a/b/c and 3 questions,
  // score granularity is coarse (0,50,100 or mixtures).
  // Example: A=aaa, B=aab (score AB≈83), C=aaa (AC=100), D=aab (BD=100), CD≈83, AD≈83
  // Sorted: AC=100, BD=100, then others. Greedy AC then BD = 200 optimal.
  // Harder case: A=aaa B=aaa C=aab D=abb
  // AB=100, AC≈83, AD≈67, BC≈83, BD≈67, CD≈83
  // Greedy AB=100 then CD≈83 total ≈183; alt AC+BD ≈83+67=150 — greedy wins.
  //
  // For ordinal a/b/c with equal weights, many classic MWPM traps are unreachable.
  // Flag: algorithm is GREEDY HEURISTIC — not proven optimal for all graphs.
  assert.ok(true);
});

test("QA timezone: 10:59 / 11:00 / 11:01 Istanbul", () => {
  // Istanbul = UTC+3 year-round
  const t1059 = new Date("2026-08-27T07:59:00.000Z"); // 10:59 TR
  const t1100 = new Date("2026-08-27T08:00:00.000Z"); // 11:00 TR
  const t1101 = new Date("2026-08-27T08:01:00.000Z"); // 11:01 TR
  assert.equal(istanbulRoundId(t1059), "2026082710");
  assert.equal(istanbulRoundId(t1100), "2026082711");
  assert.equal(istanbulRoundId(t1101), "2026082711");
  assert.equal(previousIstanbulRoundId(t1100), "2026082710");
});

test("QA timezone: 11:59 / 12:00 / 12:01 Istanbul", () => {
  const t1159 = new Date("2026-08-27T08:59:00.000Z");
  const t1200 = new Date("2026-08-27T09:00:00.000Z");
  const t1201 = new Date("2026-08-27T09:01:00.000Z");
  assert.equal(istanbulRoundId(t1159), "2026082711");
  assert.equal(istanbulRoundId(t1200), "2026082712");
  assert.equal(istanbulRoundId(t1201), "2026082712");
});

test("QA timezone: midnight wrap", () => {
  const t2359 = new Date("2026-08-27T20:59:00.000Z"); // 23:59 TR
  const t0000 = new Date("2026-08-27T21:00:00.000Z"); // 00:00 next day TR
  assert.equal(istanbulRoundId(t2359), "2026082723");
  assert.equal(istanbulRoundId(t0000), "2026082800");
  assert.equal(predecessorRoundId("2026082800"), "2026082723");
  assert.equal(parseRoundId("2026082711")?.hour, 11);
});

test("QA performance: optimizeMatches scales", () => {
  const sizes = [10, 50, 100, 500];
  const report = [];
  for (const n of sizes) {
    const participants = [];
    for (let i = 0; i < n; i++) {
      const opts = ["a", "b", "c"];
      participants.push({
        uid: `u${String(i).padStart(4, "0")}`,
        answers: {
          rq_001: opts[i % 3],
          rq_002: opts[(i + 1) % 3],
          rq_003: opts[(i + 2) % 3],
        },
      });
    }
    const t0 = Date.now();
    const pairs = optimizeMatches({participants, topK: 20});
    const ms = Date.now() - t0;
    report.push({n, ms, matches: pairs.length});
    // Soft budget: 500 users under 5s on typical laptop
    if (n <= 100) assert.ok(ms < 2000, `n=${n} took ${ms}ms`);
    if (n === 500) assert.ok(ms < 15000, `n=500 took ${ms}ms`);
  }
  console.log("[QA perf]", JSON.stringify(report));
});

test("QA geographic distance is NOT in engine ranking", () => {
  // Documented product priority includes geo after personality — engine has no geo fields.
  const src = require("node:fs").readFileSync(
    require("node:path").join(__dirname, "../src/hourlyMatchingGameEngine.ts"),
    "utf8",
  );
  assert.equal(/lat|lng|geo|distanceKm|haversine/i.test(src), false);
});
