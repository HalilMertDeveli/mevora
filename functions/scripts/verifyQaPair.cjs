const {
  optimizeMatches,
  scoreAnswerSnapshots,
} = require("../lib/hourlyMatchingGameEngine.js");

const a = {rq_001: "a", rq_002: "b", rq_003: "c"};
const scored = scoreAnswerSnapshots(a, a);
const pairs = optimizeMatches({
  participants: [
    {uid: "qa_hour_user_a", answers: a},
    {uid: "qa_hour_user_b", answers: a},
  ],
});
console.log(
  JSON.stringify({
    score: scored.score,
    pairCount: pairs.length,
    pair: pairs[0] || null,
  }),
);
