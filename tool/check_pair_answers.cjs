const {
  scoreRelationshipCompatibility,
  relationshipQuestionSets,
} = require("../functions/lib/relationshipCompatibility.js");
const {
  questionAlignmentTier,
  compareDiscoveryCandidates,
} = require("../functions/lib/boost/ranking.js");

const a = {
  rq_018: "b",
  rq_007: "a",
  rq_012: "a",
  rq_001: "a",
  rq_013: "c",
  rq_015: "b",
  rq_006: "a",
  rq_002: "b",
  rq_017: "b",
  rq_010: "b",
  rq_003: "c",
  rq_014: "b",
  rq_011: "a",
  rq_005: "a",
  rq_004: "a",
  rq_016: "b",
};
const b = {
  rq_008: "b",
  rq_010: "b",
  rq_002: "b",
  rq_001: "a",
  rq_006: "a",
  rq_016: "b",
  rq_007: "a",
  rq_018: "b",
  rq_017: "b",
  rq_012: "a",
  rq_009: "b",
  rq_003: "a",
  rq_013: "c",
  rq_004: "a",
  rq_011: "a",
  rq_014: "b",
  rq_005: "a",
  rq_015: "b",
};

const sets = relationshipQuestionSets();
const set05 = sets[4];
console.log("set_05", set05);
const fv = {};
const fo = {};
for (const id of set05) {
  fv[id] = a[id];
  fo[id] = b[id];
}
const session = scoreRelationshipCompatibility(fv, fo);
console.log("session score", session);
for (const id of set05) {
  console.log(
    id,
    a[id],
    "vs",
    b[id],
    a[id] === b[id] ? "MATCH" : "NO MATCH",
  );
}
const full = scoreRelationshipCompatibility(a, b);
console.log("full", full);

const farExact = {
  uid: "hilal",
  relationshipAlignedCount: full.alignedCount,
  distanceKm: 0.09,
  compatibilityScore: 70,
};
const nearNone = {
  uid: "other",
  relationshipAlignedCount: 0,
  distanceKm: 0.01,
  compatibilityScore: 99,
};
console.log(
  "priority vs closer non-align",
  compareDiscoveryCandidates(farExact, nearNone, new Set(), 50) < 0
    ? "PASS (aligned first)"
    : "FAIL",
);
console.log("tier", questionAlignmentTier(farExact));
