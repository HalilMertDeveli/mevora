/**
 * The finite-batch contract of Mevora Picks, end to end against the in-memory
 * Firestore: the real pool scan, the real eligibility chain, the real batch
 * document.
 *
 * Mevora is not an endless feed. A member meets a fixed, small number of
 * strong candidates per Istanbul day; deciding quickly never buys more; only
 * a Pick that stops being eligible (block, deletion, hidden) may be replaced,
 * within a fixed allowance; and quality is never lowered to reach the count.
 *
 * Every rule runs once per supported daily target (10 and 15), so the owner
 * can choose either without re-proving the product.
 */
const {beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

const db = createFakeFirestore();
installFirebaseAdminStubs({db});

const {
  LEGACY_BATCH_SIZING,
  PICKS_CONFIG,
  PICKS_DAILY_TARGET,
  PICKS_DAILY_TARGET_OPTIONS,
  PICKS_SIZING,
  picksSizing,
} = require("../lib/picks/config.js");
const lifecycle = require("../lib/picks/lifecycle.js");
const {
  attributePickMatch,
  picksDocPath,
  recordPickDecision,
  servePicks,
} = require("../lib/picks/service.js");
const {loadDiscoveryViewerContext} = require("../lib/discoveryPool.js");
const {getMevoraPicks} = require("../lib/picks/index.js");

const VIEWER = "viewer";
const INTERVAL = PICKS_CONFIG.topUpMinIntervalMs;

/**
 * Noon of the current Picks day (the logical day starts at Istanbul midnight).
 *
 * These tests step time forward from "now" by up to seven top-up intervals
 * (3.5 h). Measured from the real clock, those steps crossed the daily refresh
 * whenever the suite ran after 20:30 Istanbul time: the batch under test was
 * regenerated and the assertions failed until midnight — every evening, on
 * every pull request. From noon no step reaches the end of the day.
 */
function testNow() {
  const offsetMs = PICKS_CONFIG.logicalDayUtcOffsetMinutes * 60_000;
  const dayMs = 24 * 60 * 60 * 1000;
  const dayStart = Math.floor((Date.now() + offsetMs) / dayMs) * dayMs - offsetMs;
  return dayStart + dayMs / 2;
}

const approvedPhotos = [1, 2, 3].map((n) => ({
  id: `p${n}`,
  downloadUrl: `https://example.test/${n}.jpg`,
  moderationStatus: "approved",
  order: n,
}));

function profile(uid, overrides = {}) {
  return {
    uid,
    displayName: uid,
    age: 28,
    gender: "man",
    interestedIn: "women",
    isDiscoverable: true,
    profileCompleted: true,
    photos: approvedPhotos,
    relationshipGoal: "longTerm",
    interests: ["hiking", "jazz", "cooking", "chess"],
    lifestyle: ["nonsmoker", "earlybird"],
    lastActiveAt: Timestamp.fromMillis(testNow()),
    updatedAt: 1000,
    ...overrides,
  };
}

/** Nothing in common with the viewer beyond being active: below the quality floor. */
const WEAK = {relationshipGoal: "casual", interests: ["x9"], lifestyle: ["smoker"]};

/**
 * A world with `strong` candidates who clear the quality floor and `weak`
 * ones who do not. The weak ones are the most recently updated, so the scan
 * meets them first: if anything were used as filler, it would be them.
 */
function seedWorld({strong = 0, weak = 0, extraViewers = []} = {}) {
  const seed = {
    [`users/${VIEWER}`]: {uid: VIEWER},
    [`profiles/${VIEWER}`]: profile(VIEWER, {gender: "woman", interestedIn: "men", updatedAt: 1}),
  };
  for (const uid of extraViewers) {
    seed[`users/${uid}`] = {uid};
    seed[`profiles/${uid}`] = profile(uid, {gender: "woman", interestedIn: "men", updatedAt: 2});
  }
  for (let i = 0; i < weak; i++) {
    seed[`users/w${i}`] = {uid: `w${i}`};
    seed[`profiles/w${i}`] = profile(`w${i}`, {...WEAK, updatedAt: 90_000 - i});
  }
  for (let i = 0; i < strong; i++) {
    seed[`users/s${i}`] = {uid: `s${i}`};
    seed[`profiles/s${i}`] = profile(`s${i}`, {updatedAt: 50_000 - i});
  }
  db.reset(seed);
}

async function serve(nowMs, sizing, uid = VIEWER) {
  const {viewer, boostSessions} = await loadDiscoveryViewerContext(db, uid, {uid});
  return servePicks({db, viewer, boostSessions, nowMs, sizing});
}

function stored(uid = VIEWER) {
  return lifecycle.parseBatch(db.read(picksDocPath(uid)));
}

async function pass(candidateUid, viewerUid = VIEWER) {
  await db.doc(`users/${viewerUid}/passedUsers/${candidateUid}`).set({toUserId: candidateUid});
  await recordPickDecision({db, viewerUid, candidateUid, decision: "passed"});
}

async function like(candidateUid, viewerUid = VIEWER) {
  await db
    .doc(`likes/${viewerUid}_${candidateUid}`)
    .set({fromUserId: viewerUid, toUserId: candidateUid, action: "like"});
  await recordPickDecision({db, viewerUid, candidateUid, decision: "liked"});
}

async function block(blocker, blocked) {
  await db.doc(`blocks/${blocker}_${blocked}`).set({blockerId: blocker, blockedUserId: blocked});
  await db.doc(`users/${blocker}/blockedUsers/${blocked}`).set({blockedUserId: blocked});
}

const uidsOf = (result) => result.picks.map((item) => item.uid);

/** A strong candidate who joins after today's batch was made. */
function latecomer(uid) {
  return profile(uid, {updatedAt: 99_000});
}

describe("Picks sizing comes from one place", () => {
  it("the default daily target is 10 and is one of the supported options", () => {
    assert.equal(PICKS_DAILY_TARGET, 10);
    assert.ok(PICKS_DAILY_TARGET_OPTIONS.includes(PICKS_DAILY_TARGET));
    assert.deepEqual([...PICKS_DAILY_TARGET_OPTIONS], [10, 15]);
  });

  it("every count derives from the target", () => {
    assert.deepEqual(picksSizing(10), {
      targetCount: 10,
      maxReplacementsPerBatch: 3,
      maxDeliveredPerBatch: 13,
      scanPageSize: 40,
      scanMaxPages: 4,
      scanShortlistSize: 60,
    });
    assert.deepEqual(picksSizing(15), {
      targetCount: 15,
      maxReplacementsPerBatch: 4,
      maxDeliveredPerBatch: 19,
      scanPageSize: 40,
      scanMaxPages: 6,
      scanShortlistSize: 90,
    });
    // The legacy config object carries the same numbers, not its own copies.
    for (const key of Object.keys(PICKS_SIZING)) {
      assert.equal(PICKS_CONFIG[key], PICKS_SIZING[key], key);
    }
  });

  it("the callable reports the configured target to the app", async () => {
    seedWorld({strong: PICKS_DAILY_TARGET + 2});
    const result = await callAs(getMevoraPicks, VIEWER);
    assert.equal(result.targetCount, PICKS_DAILY_TARGET);
    assert.equal(result.picks.length, PICKS_DAILY_TARGET);
  });

  it("a batch written before sizing existed keeps its own size until it expires", async () => {
    seedWorld({strong: 20});
    const nowMs = testNow();
    const legacy = lifecycle.newBatch({
      generationId: "legacy",
      nowMs,
      picks: lifecycle.buildStoredPicks(
        "legacy",
        ["s0", "s1", "s2", "s3", "s4", "s5"].map((uid, rank) => ({
          candidateUid: uid, rank, pickType: "bestOverall", labels: ["bestOverall"],
          reasons: [], overallScore: 80, isBoosted: false, selectionStrategy: "exploit",
        })),
        new Map(),
        nowMs,
      ),
      cooldowns: {},
    });
    delete legacy.targetCount;
    delete legacy.maxDeliveredCount;
    await db.doc(picksDocPath(VIEWER)).set(legacy);
    const result = await serve(nowMs + INTERVAL + 1);
    assert.equal(result.generationId, "legacy");
    assert.equal(result.targetCount, LEGACY_BATCH_SIZING.targetCount);
    assert.equal(result.picks.length, 6, "a deploy must not top up a live legacy batch");
  });
});

for (const target of PICKS_DAILY_TARGET_OPTIONS) {
  const sizing = picksSizing(target);
  const allowance = sizing.maxReplacementsPerBatch;

  describe(`finite daily batch — target ${target}`, () => {
    beforeEach(() => seedWorld({strong: 3 * target}));

    it(`a new daily batch holds exactly ${target}, even with ${3 * target} strong candidates`, async () => {
      const result = await serve(testNow(), sizing);
      assert.equal(result.status, "ready");
      assert.equal(result.picks.length, target);
      assert.equal(result.targetCount, target);
      const batch = stored();
      assert.equal(batch.deliveredCount, target);
      assert.equal(batch.targetCount, target);
      assert.equal(batch.maxDeliveredCount, target + allowance);
    });

    it("20 strong candidates still yield only the target", async () => {
      seedWorld({strong: 20});
      const result = await serve(testNow(), sizing);
      assert.equal(result.picks.length, Math.min(20, target));
      assert.equal(stored().deliveredCount, Math.min(20, target));
    });

    it("passing five Picks at once brings nobody new, however long the member waits today", async () => {
      const now = testNow();
      const first = await serve(now, sizing);
      for (const uid of uidsOf(first).slice(0, 5)) await pass(uid);
      for (const later of [now + 1, now + INTERVAL + 1, now + 3 * INTERVAL + 1]) {
        const result = await serve(later, sizing);
        assert.equal(result.generationId, first.generationId);
        assert.deepEqual(uidsOf(result), uidsOf(first).slice(5));
      }
      assert.equal(stored().deliveredCount, target);
    });

    it("a liked slot is not refilled the same day", async () => {
      const now = testNow();
      const first = await serve(now, sizing);
      await like(uidsOf(first)[0]);
      const later = await serve(now + INTERVAL + 1, sizing);
      assert.equal(later.picks.length, target - 1);
      assert.equal(stored().deliveredCount, target);
    });

    it("a matched slot is not refilled the same day", async () => {
      const now = testNow();
      const first = await serve(now, sizing);
      const partner = uidsOf(first)[0];
      const matchId = [VIEWER, partner].sort().join("_");
      await like(partner);
      await db.doc(`matches/${matchId}`).set({userIds: [VIEWER, partner].sort(), isActive: true});
      await attributePickMatch({db, matchRef: db.doc(`matches/${matchId}`), uidA: VIEWER, uidB: partner});
      const later = await serve(now + INTERVAL + 1, sizing);
      assert.equal(later.picks.length, target - 1);
      assert.equal(later.picks.some((item) => item.uid === partner), false);
      assert.equal(stored().picks.find((pick) => pick.candidateUid === partner).state, "matched");
      assert.equal(stored().deliveredCount, target);
    });

    it("a Pick lost to a block gets a controlled replacement", async () => {
      const now = testNow();
      const first = await serve(now, sizing);
      const [a, b] = uidsOf(first);
      await block(VIEWER, a);
      await block(VIEWER, b);
      const later = await serve(now + INTERVAL + 1, sizing);
      assert.equal(later.generationId, first.generationId);
      assert.equal(later.picks.length, target);
      assert.equal(later.picks.some((item) => item.uid === a || item.uid === b), false);
      assert.equal(stored().deliveredCount, target + 2);
    });

    it(`replacements never take the day past ${target + allowance} people`, async () => {
      let now = testNow();
      const everShown = new Set();
      let result = await serve(now, sizing);
      for (let round = 0; round < 6; round++) {
        for (const uid of uidsOf(result)) everShown.add(uid);
        for (const uid of uidsOf(result)) await block(VIEWER, uid);
        now += INTERVAL + 1;
        result = await serve(now, sizing);
      }
      for (const uid of uidsOf(result)) everShown.add(uid);
      assert.equal(everShown.size, target + allowance);
      assert.equal(stored().deliveredCount, target + allowance);
      assert.equal(result.picks.length, 0);
    });

    it("few strong candidates → lowSupply, and weak ones are never used as filler", async () => {
      seedWorld({strong: 3, weak: 3 * target});
      const result = await serve(testNow(), sizing);
      assert.equal(result.status, "lowSupply");
      assert.deepEqual(uidsOf(result).sort(), ["s0", "s1", "s2"]);
      // Waiting for a top-up does not lower the bar either.
      const later = await serve(testNow() + INTERVAL + 1, sizing);
      assert.deepEqual(uidsOf(later).sort(), ["s0", "s1", "s2"]);
      assert.equal(later.status, "lowSupply");
    });

    it("reopening the same day keeps the generation and the order, and writes nothing", async () => {
      const now = testNow();
      const first = await serve(now, sizing);
      db.resetStats();
      for (const later of [now + 1000, now + 2 * INTERVAL]) {
        const again = await serve(later, sizing);
        assert.equal(again.generationId, first.generationId);
        assert.deepEqual(uidsOf(again), uidsOf(first));
        assert.deepEqual(again.picks.map((item) => item.pick.rank), first.picks.map((item) => item.pick.rank));
      }
      assert.equal(db.stats().writes, 0);
    });

    it("the next Istanbul day brings a new batch — not a second earlier", async () => {
      const now = testNow();
      const first = await serve(now, sizing);
      const boundary = lifecycle.nextLogicalDayStartMs(now);
      // Istanbul midnight is 21:00 UTC (UTC+3, no DST).
      assert.equal(new Date(boundary).getUTCHours(), 21);
      const lastSecond = await serve(boundary - 1, sizing);
      assert.equal(lastSecond.generationId, first.generationId);
      const nextDay = await serve(boundary, sizing);
      assert.notEqual(nextDay.generationId, first.generationId);
      assert.equal(nextDay.picks.length, target);
      // Yesterday's undecided people rest; the new day brings new people.
      const yesterday = new Set(uidsOf(first));
      assert.equal(nextDay.picks.some((item) => yesterday.has(item.uid)), false);
    });

    it("a block hides the Pick at once, from both sides, without waiting for a top-up", async () => {
      const now = testNow();
      const mine = await serve(now, sizing);
      const other = uidsOf(mine)[0];
      // The other member's own Picks contain the viewer (they are the only woman).
      const theirs = await serve(now, sizing, other);
      assert.ok(uidsOf(theirs).includes(VIEWER));
      await block(VIEWER, other);
      const mineAfter = await serve(now + 1, sizing);
      const theirsAfter = await serve(now + 1, sizing, other);
      assert.equal(uidsOf(mineAfter).includes(other), false);
      assert.equal(uidsOf(theirsAfter).includes(VIEWER), false);
    });

    it("a block written only by the other side (client subcollection) also hides the Pick", async () => {
      const now = testNow();
      const mine = await serve(now, sizing);
      const other = uidsOf(mine)[1];
      await db.doc(`users/${other}/blockedUsers/${VIEWER}`).set({blockedUserId: VIEWER});
      const after = await serve(now + 1, sizing);
      assert.equal(uidsOf(after).includes(other), false);
    });

    it("two accounts never share or mix a batch", async () => {
      seedWorld({strong: 3 * target, extraViewers: ["viewer2"]});
      const now = testNow();
      const a = await serve(now, sizing, VIEWER);
      const b = await serve(now, sizing, "viewer2");
      assert.notEqual(a.generationId, b.generationId);
      assert.equal(stored(VIEWER).generationId, a.generationId);
      assert.equal(stored("viewer2").generationId, b.generationId);
      // One member's decisions never touch the other's batch.
      await pass(uidsOf(a)[0], VIEWER);
      const bAgain = await serve(now + 1, sizing, "viewer2");
      assert.deepEqual(uidsOf(bAgain), uidsOf(b));
      const aAgain = await serve(now + 1, sizing, VIEWER);
      assert.equal(aAgain.generationId, a.generationId);
      assert.equal(uidsOf(aAgain).includes(uidsOf(a)[0]), false);
    });

    it(
      "two concurrent opens run one expensive generation",
      async () => {
        const now = testNow();
        const poolPages = () => db.stats().queries.filter((query) => query.path === "profiles").length;
        // Baseline: what one generation scans in this world.
        await serve(now, sizing);
        const onePass = poolPages();
        assert.ok(onePass > 0);
        seedWorld({strong: 3 * target});
        const [x, y] = await Promise.all([serve(now, sizing), serve(now, sizing)]);
        assert.equal(x.generationId, y.generationId);
        assert.deepEqual(uidsOf(x), uidsOf(y));
        assert.equal(poolPages(), onePass, "the second open must not scan the pool again");
        // Five at once, the same.
        seedWorld({strong: 3 * target});
        const many = await Promise.all(Array.from({length: 5}, () => serve(now, sizing)));
        assert.equal(new Set(many.map((result) => result.generationId)).size, 1);
        assert.equal(poolPages(), onePass);
        assert.equal(db.read(picksDocPath(VIEWER)).generationLease, undefined, "the lease is released");
      },
    );

    it("a lease left by a crashed generation is taken over once it lapses", async () => {
      const now = testNow();
      await db.doc(picksDocPath(VIEWER)).set({generationLease: {token: "dead", untilMs: now - 1}});
      const result = await serve(now, sizing);
      assert.equal(result.picks.length, target);
      assert.equal(db.read(picksDocPath(VIEWER)).generationLease, undefined);
    });

    it("a failed generation releases its lease so the next open need not wait", async () => {
      const now = testNow();
      const failing = {...db, collection: (path) => {
        if (path === "profiles") throw new Error("pool unavailable");
        return db.collection(path);
      }};
      const {viewer, boostSessions} = await loadDiscoveryViewerContext(db, VIEWER, {uid: VIEWER});
      await assert.rejects(() => servePicks({db: failing, viewer, boostSessions, nowMs: now, sizing}));
      assert.equal(db.read(picksDocPath(VIEWER))?.generationLease, undefined);
      const started = Date.now();
      const result = await serve(now + 1, sizing);
      assert.equal(result.picks.length, target);
      assert.ok(Date.now() - started < PICKS_CONFIG.generationLeaseMs / 2, "no lease wait");
    });

    it("a low-supply batch stays short today and never rescans the pool on reopen", async () => {
      seedWorld({strong: 3, weak: 5});
      const now = testNow();
      const first = await serve(now, sizing);
      assert.equal(first.status, "lowSupply");
      // More strong people join later in the day...
      for (let i = 0; i < target; i++) {
        await db.doc(`users/late${i}`).set({uid: `late${i}`});
        await db.doc(`profiles/late${i}`).set(latecomer(`late${i}`));
      }
      db.resetStats();
      const later = await serve(now + 4 * INTERVAL, sizing);
      // ...but today's batch is not refilled, and reopening costs no pool scan.
      assert.deepEqual(uidsOf(later).sort(), ["s0", "s1", "s2"]);
      assert.equal(db.stats().queries.filter((query) => query.path === "profiles").length, 0);
    });

    it("an empty replacement scan backs off: 30 min, then 1 h, then 2 h", async () => {
      // Exactly one day's worth of strong people: a replacement finds nobody.
      seedWorld({strong: target});
      const now = testNow();
      const first = await serve(now, sizing);
      await block(VIEWER, uidsOf(first)[0]);
      const pages = () => db.stats().queries.filter((query) => query.path === "profiles").length;
      const scansAt = async (at) => {
        db.resetStats();
        await serve(at, sizing);
        return pages() > 0;
      };
      assert.equal(await scansAt(now + INTERVAL - 1), false, "not before the interval");
      assert.equal(await scansAt(now + INTERVAL), true, "first replacement scan");
      assert.equal(stored().emptyTopUpStreak, 1);
      assert.equal(await scansAt(now + 2 * INTERVAL), false, "backed off to 1 h");
      assert.equal(await scansAt(now + 3 * INTERVAL), true);
      assert.equal(stored().emptyTopUpStreak, 2);
      assert.equal(await scansAt(now + 6 * INTERVAL), false, "backed off to 2 h");
      assert.equal(await scansAt(now + 7 * INTERVAL), true);
      assert.equal(stored().deliveredCount, target, "nobody was found, nobody was added");
    });
  });
}
