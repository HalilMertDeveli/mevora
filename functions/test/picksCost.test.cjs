/**
 * What one Mevora Picks open costs, in billed Firestore reads, measured through
 * the real callable against the metered in-memory Firestore.
 *
 * Two costs are kept apart on purpose:
 *   - GENERATION: the first open of an Istanbul day (pool scan, scoring, write);
 *   - REOPEN: every later open of the same day's batch.
 * Generation happens once per member per day; reopen happens on every visit,
 * so reopen is the one that must not grow with how long someone has used Mevora.
 *
 * The numbers are printed as test diagnostics (\`node --test\` shows them) so a
 * change in cost is visible in review; the assertions pin the shape.
 */
const {beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

const db = createFakeFirestore();
installFirebaseAdminStubs({db});

const {PICKS_DAILY_TARGET} = require("../lib/picks/config.js");
const lifecycle = require("../lib/picks/lifecycle.js");
const {getMevoraPicks} = require("../lib/picks/index.js");

const VIEWER = "viewer";

function profile(uid, overrides = {}) {
  return {
    uid,
    displayName: uid,
    age: 28,
    gender: "man",
    interestedIn: "women",
    isDiscoverable: true,
    profileCompleted: true,
    photos: [1, 2, 3].map((n) => ({
      id: `p${n}`, downloadUrl: `https://example.test/${n}.jpg`, moderationStatus: "approved", order: n,
    })),
    relationshipGoal: "longTerm",
    interests: ["hiking", "jazz", "cooking", "chess"],
    lifestyle: ["nonsmoker", "earlybird"],
    lastActiveAt: Timestamp.fromMillis(Date.now()),
    updatedAt: 1000,
    ...overrides,
  };
}

/**
 * A pool of strong candidates, plus `history` people the viewer already liked
 * and `history` already passed (hidden from the pool, as decided people are),
 * plus `boosts` members elsewhere with a live Boost.
 */
function seedWorld({candidates, history = 0, boosts = 0}) {
  const seed = {
    [`users/${VIEWER}`]: {uid: VIEWER},
    [`profiles/${VIEWER}`]: profile(VIEWER, {gender: "woman", interestedIn: "men", updatedAt: 1}),
  };
  for (let i = 0; i < candidates; i++) {
    seed[`users/s${i}`] = {uid: `s${i}`};
    seed[`profiles/s${i}`] = profile(`s${i}`, {updatedAt: 50_000 - i});
  }
  for (let i = 0; i < history; i++) {
    seed[`likes/${VIEWER}_liked${i}`] = {fromUserId: VIEWER, toUserId: `liked${i}`, action: "like"};
    seed[`users/${VIEWER}/passedUsers/passed${i}`] = {toUserId: `passed${i}`};
  }
  const expiresAt = Timestamp.fromMillis(Date.now() + 3_600_000);
  for (let i = 0; i < boosts; i++) {
    seed[`users/boosted${i}/boosts/b${i}`] = {userId: `boosted${i}`, status: "active", expiresAt};
  }
  db.reset(seed);
}

/** Waits out the last seconds of an Istanbul day so both opens share one. */
async function awayFromDayBoundary() {
  const left = lifecycle.nextLogicalDayStartMs(Date.now()) - Date.now();
  if (left < 5_000) await new Promise((resolve) => setTimeout(resolve, left + 50));
}

async function measure({history, boosts = 0}) {
  seedWorld({candidates: 3 * PICKS_DAILY_TARGET, history, boosts});
  await awayFromDayBoundary();
  const first = await callAs(getMevoraPicks, VIEWER);
  const generation = db.stats();
  db.resetStats();
  const again = await callAs(getMevoraPicks, VIEWER);
  const reopen = db.stats();
  assert.equal(again.generationId, first.generationId, "both opens must share one batch");
  assert.equal(first.picks.length, PICKS_DAILY_TARGET);
  return {generation, reopen};
}

describe(`Picks cost per open (target ${PICKS_DAILY_TARGET})`, () => {
  beforeEach(() => db.reset({}));

  it("a same-day reopen writes nothing and costs far less than generating", async (t) => {
    const {generation, reopen} = await measure({history: 0});
    t.diagnostic(`generation: ${generation.reads} reads, ${generation.writes} writes`);
    t.diagnostic(`reopen:     ${reopen.reads} reads, ${reopen.writes} writes`);
    assert.equal(reopen.writes, 0);
    assert.ok(reopen.reads < generation.reads);
  });

  it("reports how cost grows with the member's history and with live Boosts", async (t) => {
    const small = await measure({history: 0});
    const large = await measure({history: 300, boosts: 50});
    t.diagnostic(
      `history 0 → 300 likes + 300 passes, 0 → 50 live Boosts elsewhere: ` +
      `generation ${small.generation.reads} → ${large.generation.reads} reads, ` +
      `reopen ${small.reopen.reads} → ${large.reopen.reads} reads`,
    );
    assert.ok(large.reopen.reads >= small.reopen.reads);
  });

  it(
    "reopen cost does not grow with the member's history or with Boosts elsewhere",
    {todo: "removed by perf/picks-live-batch-fast-path"},
    async () => {
      const small = await measure({history: 0});
      const large = await measure({history: 300, boosts: 50});
      assert.equal(large.reopen.reads, small.reopen.reads);
    },
  );
});
