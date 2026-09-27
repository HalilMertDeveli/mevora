const {describe, it, beforeEach} = require("node:test");
const assert = require("node:assert/strict");

const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

/**
 * Behavioural tests for the humor callables' privacy, authorization and
 * moderation guarantees. The compiled callables run for real through
 * `.run(request)` against an in-memory Firestore; only the Admin SDK entry
 * points are swapped, and they must be swapped before the module loads.
 */
const db = createFakeFirestore();
const {auth} = installFirebaseAdminStubs({db});

const humor = require("../lib/humor/index.js");
const {
  humorScoreForPair,
  isHumorCalibrationReady,
  isValidMatchId,
} = require("../lib/humor/compatibility.js");
const {ingestHumorSourceItem} = require("../lib/humor/ingest.js");
const {HUMOR_CALIBRATION_VERSION} = require("../lib/humor/calibration.js");
const {HUMOR_CATEGORIES, normalizeProfileVector} = require("../lib/humor/categories.js");

const A = "user-a";
const B = "user-b";
const C = "user-c";
const ADMIN = "admin-1";
const MATCH = [A, B].sort().join("_");
const PAYLOAD_KEYS = ["available", "reason", "score", "strongestShared"];

// Personas on the 0..100 profile scale; unspecified dimensions sit at 50.
const WRY = {sarcasm: 85, dry: 80, wordplay: 75, silly: 30, cringe: 30, romantic: 35};
const WRY_TWIN = {sarcasm: 80, dry: 84, wordplay: 70, silly: 35, cringe: 28, romantic: 40};
const GOOFY = {silly: 85, meme: 80, absurd: 78, sarcasm: 30, dry: 30, wordplay: 28};
const ANTI_WRY = {sarcasm: 15, dry: 20, wordplay: 25, silly: 70, cringe: 70, romantic: 65};
const FLAT = {};

function profile(vector, interactionCount = 15) {
  return {
    vector: normalizeProfileVector(vector, 50),
    confidence: 0.3,
    interactionCount,
    exploredCategories: [],
    version: 1,
  };
}

function calibration(completedCount) {
  return {
    version: HUMOR_CALIBRATION_VERSION,
    completedCount,
    stage: completedCount >= 15 ? "complete" : "exploration",
    complete: completedCount >= 15,
    ratedContentIds: [],
    coveredSlots: [],
    coveredDimensions: [],
    degradedCount: 0,
  };
}

function content(overrides = {}) {
  return {
    contentId: "c1",
    type: "image",
    language: "tr",
    category: "sarcasm",
    humorTags: [],
    humorVector: {sarcasm: 0.8},
    media: {downloadUrl: "https://media.giphy.com/media/c1/giphy.gif"},
    safetyStatus: "approved",
    safetyFlags: {},
    source: {type: "internal", provider: "mevora-internal", licenseRef: null},
    active: true,
    stats: {viewCount: 0, ratingCount: 0, avgRating: 0},
    ...overrides,
  };
}

async function rejectsWith(promise, code) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code, `expected ${code}, got ${error.code}: ${error.message}`);
    return true;
  });
}

/** Every number anywhere in a payload. */
function numbersIn(value, out = []) {
  if (typeof value === "number") out.push(value);
  else if (Array.isArray(value)) value.forEach((v) => numbersIn(v, out));
  else if (value && typeof value === "object") Object.values(value).forEach((v) => numbersIn(v, out));
  return out;
}

function assertPayloadShape(result) {
  assert.deepEqual(Object.keys(result).sort(), PAYLOAD_KEYS);
  assert.equal(typeof result.available, "boolean");
  assert.ok(Array.isArray(result.strongestShared));
  for (const key of result.strongestShared) {
    assert.ok(HUMOR_CATEGORIES.includes(key), `not a category key: ${key}`);
  }
  if (result.available) {
    assert.ok(Number.isInteger(result.score) && result.score >= 0 && result.score <= 100);
    assert.equal(result.reason, null);
    // The score is the only number the caller ever sees: no peer vector
    // values, confidence or interaction count.
    assert.deepEqual(numbersIn(result), [result.score]);
  } else {
    assert.equal(result.score, null);
    assert.deepEqual(result.strongestShared, []);
    assert.ok(["building", "no-signal", "invalid-match"].includes(result.reason));
    assert.deepEqual(numbersIn(result), []);
  }
}

// --------------------------------------------------------------------------
// Pair score (pure)
// --------------------------------------------------------------------------

describe("humor pair score — centred, calibrated, peer-value free", () => {
  it("returns exactly {available, score, strongestShared, reason}", () => {
    assertPayloadShape(humorScoreForPair(profile(WRY), profile(WRY_TWIN)));
    assertPayloadShape(humorScoreForPair(profile(WRY, 3), profile(WRY_TWIN, 3)));
    assertPayloadShape(humorScoreForPair(profile(FLAT), profile(WRY)));
    const result = humorScoreForPair(profile(WRY), profile(WRY_TWIN));
    assert.equal("differences" in result, false);
    assert.equal("confidence" in result, false);
  });

  it("ranks a similar pair above a disjoint pair", () => {
    const similar = humorScoreForPair(profile(WRY), profile(WRY_TWIN));
    const disjoint = humorScoreForPair(profile(WRY), profile(GOOFY));
    assert.equal(similar.available, true);
    assert.equal(disjoint.available, true);
    assert.ok(
      similar.score > disjoint.score + 30,
      `similar ${similar.score} should clearly beat disjoint ${disjoint.score}`,
    );
    assert.ok(similar.score >= 80, `similar pair scored only ${similar.score}`);
    assert.ok(disjoint.score < 50, `disjoint pair scored ${disjoint.score}`);
  });

  it("scores an opposite pair below 40", () => {
    const opposite = humorScoreForPair(profile(WRY), profile(ANTI_WRY));
    assert.equal(opposite.available, true);
    assert.ok(opposite.score < 40, `opposite pair scored ${opposite.score}`);
    assert.deepEqual(opposite.strongestShared, []);
  });

  it("reports no-signal when either profile is flat", () => {
    assert.deepEqual(humorScoreForPair(profile(FLAT), profile(FLAT)), {
      available: false,
      score: null,
      strongestShared: [],
      reason: "no-signal",
    });
    assert.equal(humorScoreForPair(profile(WRY), profile(FLAT)).reason, "no-signal");
    assert.equal(humorScoreForPair(profile(FLAT), profile(WRY)).reason, "no-signal");
  });

  it("names shared traits in the caller's own order, not the peer's", () => {
    const caller = profile({sarcasm: 90, dry: 70});
    const peer = profile({sarcasm: 65, dry: 95});
    assert.deepEqual(humorScoreForPair(caller, peer).strongestShared, ["sarcasm", "dry"]);
    assert.deepEqual(humorScoreForPair(peer, caller).strongestShared, ["dry", "sarcasm"]);
  });

  it("stays unavailable until both sides are ready", () => {
    const ready = profile(WRY);
    for (const readiness of [
      {readyA: false, readyB: true},
      {readyA: true, readyB: false},
      {readyA: false, readyB: false},
    ]) {
      assert.equal(humorScoreForPair(ready, ready, readiness).reason, "building");
    }
    assert.equal(humorScoreForPair(ready, ready, {readyA: true, readyB: true}).available, true);
    assert.equal(humorScoreForPair(null, ready).reason, "building");
  });
});

describe("calibration readiness — the 14/15 boundary", () => {
  it("needs a completed calibration", () => {
    assert.equal(isHumorCalibrationReady(calibration(14), profile(WRY, 14)), false);
    assert.equal(isHumorCalibrationReady(calibration(15), profile(WRY, 15)), true);
  });

  it("an in-progress calibration is not ready, however many ratings exist", () => {
    assert.equal(isHumorCalibrationReady(calibration(9), profile(WRY, 40)), false);
  });

  it("a pre-calibration profile falls back to 15 interactions", () => {
    assert.equal(isHumorCalibrationReady(undefined, profile(WRY, 14)), false);
    assert.equal(isHumorCalibrationReady(undefined, profile(WRY, 15)), true);
    assert.equal(isHumorCalibrationReady(undefined, null), false);
  });
});

// --------------------------------------------------------------------------
// getMatchHumorCompatibility (callable)
// --------------------------------------------------------------------------

function seedCompatibility(overrides = {}) {
  db.reset({
    [`matches/${MATCH}`]: {userIds: [A, B], isActive: true},
    [`users/${A}/humor/summary`]: profile(WRY),
    [`users/${B}/humor/summary`]: profile(WRY_TWIN),
    [`users/${C}/humor/summary`]: profile(GOOFY),
    [`users/${A}/humor/calibration`]: calibration(15),
    [`users/${B}/humor/calibration`]: calibration(15),
    [`users/${C}/humor/calibration`]: calibration(15),
    ...overrides,
  });
}

describe("getMatchHumorCompatibility — authorization", () => {
  beforeEach(() => seedCompatibility());

  it("requires sign-in", async () => {
    await rejectsWith(callAs(humor.getMatchHumorCompatibility, null, {matchId: MATCH}), "unauthenticated");
  });

  it("rejects a slash-containing matchId even when it points at a forged document", async () => {
    // The attack: a participant writes a message carrying its own `userIds`
    // (the message rule has no key allowlist) and asks for "matches/M/messages/X",
    // which would pair them with any victim uid.
    await db.doc(`matches/${MATCH}/messages/forged`).set({
      senderId: A,
      receiverId: B,
      userIds: [A, C],
      isActive: true,
    });
    for (const matchId of [
      `${MATCH}/messages/forged`,
      "a/b",
      `../${MATCH}`,
      "",
      "   ",
      "x".repeat(129),
      "bad id",
      "a.b",
    ]) {
      await rejectsWith(
        callAs(humor.getMatchHumorCompatibility, A, {matchId}),
        "invalid-argument",
      );
    }
    for (const matchId of [42, null, undefined, {path: MATCH}, [MATCH]]) {
      await rejectsWith(
        callAs(humor.getMatchHumorCompatibility, A, {matchId}),
        "invalid-argument",
      );
    }
  });

  it("accepts only canonical-looking ids", () => {
    assert.equal(isValidMatchId(MATCH), true);
    assert.equal(isValidMatchId("x".repeat(128)), true);
    assert.equal(isValidMatchId("x".repeat(129)), false);
    assert.equal(isValidMatchId("a/b"), false);
  });

  it("an unknown match is not-found", async () => {
    await rejectsWith(
      callAs(humor.getMatchHumorCompatibility, A, {matchId: "no_such_match"}),
      "not-found",
    );
  });

  it("a non-member is refused", async () => {
    await rejectsWith(callAs(humor.getMatchHumorCompatibility, C, {matchId: MATCH}), "permission-denied");
  });

  it("an inactive match is refused, including one with no isActive field", async () => {
    await db.doc(`matches/${MATCH}`).set({userIds: [A, B], isActive: false});
    await rejectsWith(callAs(humor.getMatchHumorCompatibility, A, {matchId: MATCH}), "permission-denied");
    await db.doc(`matches/${MATCH}`).set({userIds: [A, B]});
    await rejectsWith(callAs(humor.getMatchHumorCompatibility, A, {matchId: MATCH}), "permission-denied");
  });

  it("a malformed match returns the full invalid-match payload", async () => {
    const expected = {available: false, score: null, strongestShared: [], reason: "invalid-match"};
    await db.doc("matches/three_way").set({userIds: [A, B, C], isActive: true});
    assert.deepEqual(
      await callAs(humor.getMatchHumorCompatibility, A, {matchId: "three_way"}),
      expected,
    );
    await db.doc("matches/solo").set({userIds: [A], isActive: true});
    assert.deepEqual(await callAs(humor.getMatchHumorCompatibility, A, {matchId: "solo"}), expected);
    await db.doc("matches/self_pair").set({userIds: [A, A], isActive: true});
    assert.deepEqual(
      await callAs(humor.getMatchHumorCompatibility, A, {matchId: "self_pair"}),
      expected,
    );
  });
});

describe("getMatchHumorCompatibility — payload and gating", () => {
  beforeEach(() => seedCompatibility());

  it("both calibrated: a score and category keys only", async () => {
    const result = await callAs(humor.getMatchHumorCompatibility, A, {matchId: MATCH});
    assert.equal(result.available, true);
    assertPayloadShape(result);
    // Nothing of the peer's profile leaks: none of B's dimension values, its
    // confidence or its interaction count appears anywhere in the payload.
    const peer = profile(WRY_TWIN);
    const serialized = JSON.stringify(result);
    for (const dim of HUMOR_CATEGORIES) {
      assert.equal(serialized.includes(`"${dim}":`), false);
    }
    assert.equal(serialized.includes(String(peer.confidence)), false);
  });

  it("is building while the peer is at 14 of 15 and opens at 15", async () => {
    await db.doc(`users/${B}/humor/calibration`).set(calibration(14));
    const at14 = await callAs(humor.getMatchHumorCompatibility, A, {matchId: MATCH});
    assert.deepEqual(at14, {available: false, score: null, strongestShared: [], reason: "building"});

    await db.doc(`users/${B}/humor/calibration`).set(calibration(15));
    const at15 = await callAs(humor.getMatchHumorCompatibility, A, {matchId: MATCH});
    assert.equal(at15.available, true);
  });

  it("is building while the caller is still calibrating, even with many ratings", async () => {
    await db.doc(`users/${A}/humor/calibration`).set(calibration(9));
    await db.doc(`users/${A}/humor/summary`).set(profile(WRY, 40));
    const result = await callAs(humor.getMatchHumorCompatibility, A, {matchId: MATCH});
    assert.equal(result.reason, "building");
  });

  it("legacy profiles without a calibration doc use the 15-interaction fallback", async () => {
    await db.doc(`users/${B}/humor/calibration`).delete();
    await db.doc(`users/${B}/humor/summary`).set(profile(WRY_TWIN, 14));
    assert.equal(
      (await callAs(humor.getMatchHumorCompatibility, A, {matchId: MATCH})).reason,
      "building",
    );
    await db.doc(`users/${B}/humor/summary`).set(profile(WRY_TWIN, 15));
    assert.equal(
      (await callAs(humor.getMatchHumorCompatibility, A, {matchId: MATCH})).available,
      true,
    );
  });

  it("a peer who never tried Humor Lab is building, not an error", async () => {
    await db.doc(`users/${B}/humor/calibration`).delete();
    await db.doc(`users/${B}/humor/summary`).delete();
    const result = await callAs(humor.getMatchHumorCompatibility, A, {matchId: MATCH});
    assertPayloadShape(result);
    assert.equal(result.reason, "building");
  });

  it("a calibrated but flat peer is no-signal", async () => {
    await db.doc(`users/${B}/humor/summary`).set(profile(FLAT, 15));
    const result = await callAs(humor.getMatchHumorCompatibility, A, {matchId: MATCH});
    assertPayloadShape(result);
    assert.equal(result.reason, "no-signal");
  });
});

// --------------------------------------------------------------------------
// reportHumorContent (callable)
// --------------------------------------------------------------------------

describe("reportHumorContent", () => {
  beforeEach(() => {
    db.reset({
      "humorContent/c1": content({contentId: "c1"}),
      "humorContent/c2": content({contentId: "c2"}),
    });
  });

  it("rejects malformed content ids without writing anything", async () => {
    const before = db.paths();
    for (const contentId of ["x/y", "x/y/z", "", "   ", "a".repeat(129), "c 1", 42, null, undefined]) {
      await rejectsWith(callAs(humor.reportHumorContent, A, {contentId, reason: "spam"}), "invalid-argument");
    }
    assert.deepEqual(db.paths(), before);
  });

  it("rejects content that does not exist without writing anything", async () => {
    const before = db.paths();
    await rejectsWith(callAs(humor.reportHumorContent, A, {contentId: "ghost"}), "not-found");
    assert.deepEqual(db.paths(), before);
  });

  it("files a report, queues it and hides the item from the reporter", async () => {
    const result = await callAs(humor.reportHumorContent, A, {
      contentId: "c1",
      reason: "offensive",
      details: "  not funny at all  ",
    });
    assert.deepEqual(result, {ok: true});

    const report = db.read(`humorReports/${A}_c1`);
    assert.equal(report.reporterId, A);
    assert.equal(report.contentId, "c1");
    assert.equal(report.reason, "offensive");
    assert.equal(report.details, "not funny at all");
    assert.equal(report.status, "open");
    assert.ok(report.createdAt);

    const queue = db.read("humorModerationQueue/c1");
    assert.equal(queue.status, "needs_review");
    assert.equal(queue.reportCount, 1);
    assert.equal(queue.lastReporterId, A);

    // Contract C4: the marker keeps the item out of this user's feed and
    // calibration; it has no rating and no profile effect.
    const marker = db.read(`users/${A}/humorInteractions/c1`);
    assert.deepEqual(Object.keys(marker).sort(), [
      "contentId",
      "createdAt",
      "reported",
      "skipped",
      "updatedAt",
    ]);
    assert.equal(marker.reported, true);
    assert.equal(marker.skipped, true);
    assert.equal(db.has(`users/${A}/humor/summary`), false);
    assert.equal(db.has(`users/${A}/humor/calibration`), false);
    assert.deepEqual(db.read("humorContent/c1").stats, {viewCount: 0, ratingCount: 0, avgRating: 0});
  });

  it("a repeat report by the same user changes nothing", async () => {
    await callAs(humor.reportHumorContent, A, {contentId: "c1", reason: "spam"});
    const first = db.read(`humorReports/${A}_c1`);
    await callAs(humor.reportHumorContent, A, {contentId: "c1", reason: "offensive", details: "again"});
    const second = db.read(`humorReports/${A}_c1`);
    assert.deepEqual(second, first);
    assert.equal(db.read("humorModerationQueue/c1").reportCount, 1);
  });

  it("counts distinct reporters", async () => {
    await callAs(humor.reportHumorContent, A, {contentId: "c1"});
    await callAs(humor.reportHumorContent, B, {contentId: "c1"});
    const queue = db.read("humorModerationQueue/c1");
    assert.equal(queue.reportCount, 2);
    assert.equal(queue.lastReporterId, B);
  });

  it("does not reopen a resolved report", async () => {
    db.reset({
      "humorContent/c1": content(),
      [`humorReports/${A}_c1`]: {reporterId: A, contentId: "c1", status: "resolved", resolution: "approved"},
    });
    await callAs(humor.reportHumorContent, A, {contentId: "c1"});
    assert.equal(db.read(`humorReports/${A}_c1`).status, "resolved");
  });

  it("never resets an admin decision on the queue", async () => {
    db.reset({
      "humorContent/c1": content(),
      "humorModerationQueue/c1": {contentId: "c1", status: "approved", moderatedBy: ADMIN, reportCount: 1},
    });
    await callAs(humor.reportHumorContent, B, {contentId: "c1"});
    const queue = db.read("humorModerationQueue/c1");
    assert.equal(queue.status, "approved");
    assert.equal(queue.moderatedBy, ADMIN);
    assert.equal(queue.reportCount, 2);
  });

  it("keeps an existing rating when marking the item reported", async () => {
    db.reset({
      "humorContent/c1": content(),
      [`users/${A}/humorInteractions/c1`]: {
        contentId: "c1",
        rating: "funny",
        skipped: false,
        saved: false,
      },
    });
    await callAs(humor.reportHumorContent, A, {contentId: "c1"});
    const marker = db.read(`users/${A}/humorInteractions/c1`);
    assert.equal(marker.rating, "funny");
    assert.equal(marker.skipped, false);
    assert.equal(marker.reported, true);
  });

  it("normalises reason and bounds details", async () => {
    await callAs(humor.reportHumorContent, A, {contentId: "c1", reason: "<script>", details: "d".repeat(900)});
    const report = db.read(`humorReports/${A}_c1`);
    assert.equal(report.reason, "other");
    assert.equal(report.details.length, 500);
    await callAs(humor.reportHumorContent, A, {contentId: "c2", reason: 7, details: {nested: true}});
    const other = db.read(`humorReports/${A}_c2`);
    assert.equal(other.reason, "other");
    assert.equal(other.details, "");
  });
});

// --------------------------------------------------------------------------
// runHumorModeration / upsertHumorContent (admin callables)
// --------------------------------------------------------------------------

describe("runHumorModeration", () => {
  beforeEach(() => {
    auth.users.clear();
    auth.addUser(ADMIN, {admin: true});
    auth.addUser(A);
    db.reset({
      "humorContent/c1": content({contentId: "c1"}),
      "humorContent/c2": content({contentId: "c2"}),
      "humorContent/off": content({contentId: "off", active: false}),
      [`humorReports/${A}_c1`]: {reporterId: A, contentId: "c1", status: "open"},
      [`humorReports/${B}_c1`]: {reporterId: B, contentId: "c1", status: "open"},
      [`humorReports/${C}_c1`]: {
        reporterId: C,
        contentId: "c1",
        status: "resolved",
        resolvedBy: "earlier-admin",
      },
      [`humorReports/${A}_c2`]: {reporterId: A, contentId: "c2", status: "open"},
    });
  });

  it("is admin-only", async () => {
    await rejectsWith(
      callAs(humor.runHumorModeration, A, {contentId: "c1", forceStatus: "rejected"}),
      "permission-denied",
    );
  });

  it("rejects an unknown forceStatus without writing", async () => {
    const before = db.read("humorContent/c1");
    for (const forceStatus of ["banana", "APPROVED", 1, {}]) {
      await rejectsWith(
        callAs(humor.runHumorModeration, ADMIN, {contentId: "c1", forceStatus}),
        "invalid-argument",
      );
    }
    assert.deepEqual(db.read("humorContent/c1"), before);
    assert.equal(db.has("humorModerationQueue/c1"), false);
  });

  it("validates the content id", async () => {
    await rejectsWith(callAs(humor.runHumorModeration, ADMIN, {contentId: "a/b"}), "invalid-argument");
    await rejectsWith(callAs(humor.runHumorModeration, ADMIN, {contentId: "ghost"}), "not-found");
  });

  it("approval keeps an admin's deactivation unless active: true is passed", async () => {
    const kept = await callAs(humor.runHumorModeration, ADMIN, {contentId: "off", forceStatus: "approved"});
    assert.equal(kept.active, false);
    assert.equal(db.read("humorContent/off").active, false);

    const revived = await callAs(humor.runHumorModeration, ADMIN, {
      contentId: "off",
      forceStatus: "approved",
      active: true,
    });
    assert.equal(revived.active, true);
    assert.equal(db.read("humorContent/off").active, true);
  });

  it("approval leaves active content active, and active: false deactivates it", async () => {
    assert.equal((await callAs(humor.runHumorModeration, ADMIN, {contentId: "c2", forceStatus: "approved"})).active, true);
    assert.equal(db.read("humorContent/c2").active, true);
    await callAs(humor.runHumorModeration, ADMIN, {contentId: "c2", forceStatus: "approved", active: false});
    assert.equal(db.read("humorContent/c2").active, false);
  });

  it("rejection deactivates, records the decision and resolves that item's open reports", async () => {
    const result = await callAs(humor.runHumorModeration, ADMIN, {contentId: "c1", forceStatus: "rejected"});
    assert.equal(result.safetyStatus, "rejected");
    assert.equal(result.active, false);
    assert.equal(result.resolvedReports, 2);

    const item = db.read("humorContent/c1");
    assert.equal(item.safetyStatus, "rejected");
    assert.equal(item.active, false);
    const queue = db.read("humorModerationQueue/c1");
    assert.equal(queue.status, "rejected");
    assert.equal(queue.moderatedBy, ADMIN);

    for (const reporter of [A, B]) {
      const report = db.read(`humorReports/${reporter}_c1`);
      assert.equal(report.status, "resolved");
      assert.equal(report.resolution, "rejected");
      assert.equal(report.resolvedBy, ADMIN);
    }
    // Already-resolved and other-content reports are untouched.
    assert.equal(db.read(`humorReports/${C}_c1`).resolvedBy, "earlier-admin");
    assert.equal(db.read(`humorReports/${A}_c2`).status, "open");
  });

  it("a non-final status leaves reports open", async () => {
    const result = await callAs(humor.runHumorModeration, ADMIN, {contentId: "c1", forceStatus: "needs_review"});
    assert.equal(result.resolvedReports, 0);
    assert.equal(db.read(`humorReports/${A}_c1`).status, "open");
  });

  it("a report after the decision does not undo it", async () => {
    await callAs(humor.runHumorModeration, ADMIN, {contentId: "c1", forceStatus: "rejected"});
    await callAs(humor.reportHumorContent, C, {contentId: "c2"});
    await callAs(humor.reportHumorContent, "user-d", {contentId: "c1"});
    assert.equal(db.read("humorModerationQueue/c1").status, "rejected");
  });
});

describe("upsertHumorContent input validation", () => {
  beforeEach(() => {
    auth.users.clear();
    auth.addUser(ADMIN, {admin: true});
    db.reset({});
  });

  it("rejects an unknown safetyStatus and a path-like content id", async () => {
    await rejectsWith(
      callAs(humor.upsertHumorContent, ADMIN, {contentId: "n1", category: "sarcasm", safetyStatus: "ok"}),
      "invalid-argument",
    );
    await rejectsWith(
      callAs(humor.upsertHumorContent, ADMIN, {contentId: "a/b", category: "sarcasm"}),
      "invalid-argument",
    );
    assert.deepEqual(db.paths(), []);
  });
});

// --------------------------------------------------------------------------
// Provider ingest never resurrects moderated content
// --------------------------------------------------------------------------

describe("provider ingest", () => {
  const item = {
    sourceId: "abc123",
    type: "video",
    language: "tr",
    title: "komik",
    tags: ["komik"],
    media: {downloadUrl: "https://media.giphy.com/media/abc123/giphy.mp4"},
    sourceUrl: "https://giphy.com/gifs/abc123",
  };
  const contentId = "ext_giphy_abc123";

  it("leaves a rejected item rejected and inactive", async () => {
    db.reset({
      [`humorContent/${contentId}`]: content({
        contentId,
        safetyStatus: "rejected",
        active: false,
        safetyFlags: {hate: true},
      }),
    });
    const before = db.read(`humorContent/${contentId}`);
    const result = await ingestHumorSourceItem(db, item, "giphy", {probe: false});
    assert.deepEqual(result, {upserted: false, contentId, reason: "rejected"});
    assert.deepEqual(db.read(`humorContent/${contentId}`), before);
  });

  it("leaves an admin-deactivated item inactive", async () => {
    db.reset({[`humorContent/${contentId}`]: content({contentId, active: false})});
    const before = db.read(`humorContent/${contentId}`);
    const result = await ingestHumorSourceItem(db, item, "giphy", {probe: false});
    assert.equal(result.upserted, false);
    assert.equal(result.reason, "duplicate");
    assert.deepEqual(db.read(`humorContent/${contentId}`), before);
  });

  it("still ingests a genuinely new item", async () => {
    db.reset({});
    const result = await ingestHumorSourceItem(db, item, "giphy", {probe: false});
    assert.deepEqual(result, {upserted: true, contentId});
    const stored = db.read(`humorContent/${contentId}`);
    assert.equal(stored.safetyStatus, "approved");
    assert.equal(stored.active, true);
    assert.equal(stored.calibrationEligible, false);
  });
});
