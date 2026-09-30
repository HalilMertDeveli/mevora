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
const {musicScoreForPair} = require("../lib/spotifyMusic.js");
const {relationshipScoreForPair} = require("../lib/relationshipMatch.js");
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

  it("reopen cost does not grow with the member's history or with Boosts elsewhere", async () => {
    const small = await measure({history: 0});
    const large = await measure({history: 300, boosts: 50});
    assert.equal(large.reopen.reads, small.reopen.reads);
  });

  it("generating costs the same however long the member's decision history is", async () => {
    const small = await measure({history: 0});
    const large = await measure({history: 300});
    assert.equal(large.generation.reads, small.generation.reads);
  });

  it("a reopen reads neither the decision history nor the global Boost list", async () => {
    seedWorld({candidates: 3 * PICKS_DAILY_TARGET, history: 50, boosts: 5});
    await awayFromDayBoundary();
    await callAs(getMevoraPicks, VIEWER);
    db.resetStats();
    await callAs(getMevoraPicks, VIEWER);
    const queries = db.stats().queries;
    assert.equal(queries.some((query) => query.group && query.path === "boosts"), false, "no Boost scan");
    assert.equal(queries.some((query) => query.path === "profiles"), false, "no pool scan");
    // Only the pair lookups for today's Picks: none of them returns history.
    const historyDocs = queries
      .filter((query) => query.path === "likes" || query.path.endsWith("/passedUsers"))
      .reduce((sum, query) => sum + query.docs, 0);
    assert.equal(historyDocs, 0);
  });
});

describe("one read per document per request", () => {
  beforeEach(() => db.reset({}));

  function musicSummary(extraTrack) {
    return {
      spotifyConnected: true,
      musicProfile: {
        trackIds: ["t1", "t2", extraTrack],
        artistIds: ["ar1", "ar2"],
        genres: ["indie", "rock"],
        recentTrackIds: ["t1"],
        recentArtistIds: ["ar1"],
      },
      topTracks: [{id: "t1", name: "Song One", artist: "Band"}],
    };
  }

  function relationshipSummary(answers) {
    return {answers};
  }

  it("generating reads each candidate's documents once, and none again to serve them", async () => {
    seedWorld({candidates: 3 * PICKS_DAILY_TARGET});
    await awayFromDayBoundary();
    const result = await callAs(getMevoraPicks, VIEWER);
    assert.equal(result.picks.length, PICKS_DAILY_TARGET);
    const twice = [...db.stats().byPath]
      .filter(([path, count]) => /^(users|profiles|userPreferences|userLocation)\/s\d+$/.test(path) && count > 1);
    assert.deepEqual(twice, [], "no candidate document is read twice in one open");
  });

  it("the viewer's music and relationship summaries are read once per scan, not per candidate", async () => {
    seedWorld({candidates: 3 * PICKS_DAILY_TARGET});
    await db.doc(`users/${VIEWER}/music/summary`).set(musicSummary("t9"));
    await db.doc(`users/${VIEWER}/relationshipMatch/summary`)
      .set(relationshipSummary({rq_001: "a", rq_002: "b", rq_003: "c"}));
    for (let i = 0; i < 3 * PICKS_DAILY_TARGET; i++) {
      await db.doc(`users/s${i}/music/summary`).set(musicSummary(`t${i % 4}`));
      await db.doc(`users/s${i}/relationshipMatch/summary`)
        .set(relationshipSummary({rq_001: "a", rq_002: i % 2 ? "b" : "a", rq_003: "c"}));
    }
    db.resetStats();
    await awayFromDayBoundary();
    const result = await callAs(getMevoraPicks, VIEWER);
    const reads = db.stats().byPath;
    assert.equal(reads.get(`users/${VIEWER}/music/summary`), 1);
    assert.equal(reads.get(`users/${VIEWER}/relationshipMatch/summary`), 1);
    // Same scores as the one-pair scorers the match screen uses.
    for (const item of result.picks) {
      const music = await musicScoreForPair(VIEWER, item.uid);
      const relationship = await relationshipScoreForPair(VIEWER, item.uid);
      assert.equal(item.musicCompatibilityScore, music?.score ?? null, `music for ${item.uid}`);
      assert.equal(item.relationshipCompatibilityScore, relationship?.score ?? null, `relationship for ${item.uid}`);
    }
    assert.ok(result.picks.some((item) => item.musicCompatibilityScore !== null), "music was scored");
  });

  it("a viewer with no music or relationship data costs no candidate summary reads", async () => {
    seedWorld({candidates: 3 * PICKS_DAILY_TARGET});
    for (let i = 0; i < 3 * PICKS_DAILY_TARGET; i++) {
      await db.doc(`users/s${i}/music/summary`).set(musicSummary("t1"));
    }
    db.resetStats();
    await awayFromDayBoundary();
    await callAs(getMevoraPicks, VIEWER);
    const summaryReads = [...db.stats().byPath.keys()]
      .filter((path) => /^users\/s\d+\/(music|relationshipMatch)\/summary$/.test(path));
    assert.deepEqual(summaryReads, []);
  });
});

describe("pair-targeted exclusions keep the pool exact", () => {
  beforeEach(() => db.reset({}));

  it("a new batch leaves out everyone decided or blocked, in every record they can leave", async () => {
    // Exactly one day of eligible people once the eight below are left out.
    seedWorld({candidates: PICKS_DAILY_TARGET + 8});
    const pair = (uid) => [VIEWER, uid].sort().join("_");
    await db.doc(`likes/${VIEWER}_s0`).set({fromUserId: VIEWER, toUserId: "s0", action: "like"});
    await db.doc(`users/${VIEWER}/passedUsers/s1`).set({toUserId: "s1"});
    await db.doc(`likes/${VIEWER}_s2`).set({fromUserId: VIEWER, toUserId: "s2", action: "pass"});
    await db.doc(`matches/${pair("s3")}`).set({userIds: [VIEWER, "s3"].sort(), isActive: true});
    await db.doc(`blocks/${VIEWER}_s4`).set({blockerId: VIEWER, blockedUserId: "s4"});
    await db.doc(`blocks/s5_${VIEWER}`).set({blockerId: "s5", blockedUserId: VIEWER});
    await db.doc(`users/${VIEWER}/blockedUsers/s6`).set({blockedUserId: "s6"});
    await db.doc(`users/s7/blockedUsers/${VIEWER}`).set({blockedUserId: VIEWER});
    // A like FROM them is not a decision BY the viewer: s8 stays eligible.
    await db.doc(`likes/s8_${VIEWER}`).set({fromUserId: "s8", toUserId: VIEWER, action: "like"});
    await awayFromDayBoundary();
    const result = await callAs(getMevoraPicks, VIEWER);
    const uids = result.picks.map((item) => item.uid);
    assert.equal(uids.length, PICKS_DAILY_TARGET);
    for (const excluded of ["s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7"]) {
      assert.equal(uids.includes(excluded), false, `${excluded} must be left out`);
    }
    assert.ok(uids.includes("s8"));
  });
});

describe("the fast path stays exact", () => {
  beforeEach(() => db.reset({}));

  async function openTwice(mutate) {
    seedWorld({candidates: 3 * PICKS_DAILY_TARGET});
    await awayFromDayBoundary();
    const first = await callAs(getMevoraPicks, VIEWER);
    const uids = first.picks.map((item) => item.uid);
    await mutate(uids);
    const again = await callAs(getMevoraPicks, VIEWER);
    return {first, again, uids, againUids: again.picks.map((item) => item.uid)};
  }

  it("a decision stored canonically but never mirrored into the batch still hides the Pick", async () => {
    // recordPickDecision is best effort; the canonical like/pass/match is the truth.
    const {again, uids, againUids} = await openTwice(async ([liked, passed, matched, passAsLike]) => {
      await db.doc(`likes/${VIEWER}_${liked}`).set({fromUserId: VIEWER, toUserId: liked, action: "like"});
      await db.doc(`users/${VIEWER}/passedUsers/${passed}`).set({toUserId: passed});
      await db.doc(`matches/${[VIEWER, matched].sort().join("_")}`)
        .set({userIds: [VIEWER, matched].sort(), isActive: true});
      await db.doc(`likes/${VIEWER}_${passAsLike}`)
        .set({fromUserId: VIEWER, toUserId: passAsLike, action: "pass"});
    });
    assert.deepEqual(againUids, uids.slice(4));
    const states = Object.fromEntries(
      lifecycle.parseBatch(db.read(`users/${VIEWER}/mevoraPicks/current`)).picks
        .map((pick) => [pick.candidateUid, pick.state]),
    );
    assert.equal(states[uids[0]], "liked");
    assert.equal(states[uids[1]], "passed");
    assert.equal(states[uids[2]], "matched");
    assert.equal(states[uids[3]], "passed");
    assert.equal(again.picks.length, PICKS_DAILY_TARGET - 4);
  });

  it("an ended match does not count as a decision", async () => {
    const {againUids, uids} = await openTwice(async ([ended]) => {
      await db.doc(`matches/${[VIEWER, ended].sort().join("_")}`)
        .set({userIds: [VIEWER, ended].sort(), isActive: false});
    });
    assert.deepEqual(againUids, uids);
  });

  it("a block from either side, in any of its four records, hides the Pick on the next open", async () => {
    const {againUids, uids} = await openTwice(async ([a, b, c, d]) => {
      await db.doc(`blocks/${VIEWER}_${a}`).set({blockerId: VIEWER, blockedUserId: a});
      await db.doc(`blocks/${b}_${VIEWER}`).set({blockerId: b, blockedUserId: VIEWER});
      await db.doc(`users/${VIEWER}/blockedUsers/${c}`).set({blockedUserId: c});
      await db.doc(`users/${d}/blockedUsers/${VIEWER}`).set({blockedUserId: VIEWER});
    });
    assert.deepEqual(againUids, uids.slice(4));
  });

  it("a suspended, hidden or deleted member disappears on the next open", async () => {
    const {againUids, uids} = await openTwice(async ([suspended, hidden, deleted]) => {
      await db.doc(`users/${suspended}`).set({uid: suspended, isSuspended: true});
      await db.doc(`profiles/${hidden}`).set({isDiscoverable: false}, {merge: true});
      await db.doc(`profiles/${deleted}`).delete();
    });
    assert.deepEqual(againUids, uids.slice(3));
  });
});
