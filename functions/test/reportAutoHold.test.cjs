const {beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

/**
 * A report must always reach the moderation queue, but it must not be a way
 * for one member to hide another. Before this rule every report, whatever its
 * reason, sent all of the reported member's photos to manual review — which
 * also drops the member from everyone's Picks until staff act. One "spam"
 * report was enough.
 *
 * The rule (reportAutoHold.ts): a critical reason holds at once; any other
 * reason holds only when three different members have an open report against
 * the same member within thirty days. reportUser runs here end to end against
 * the in-memory Firestore.
 */

// The callable binds getFirestore() at load, so the double goes in first.
const db = createFakeFirestore();
installFirebaseAdminStubs({db});

// reportUser stores the report with an auto id; the double has no `add`.
let autoId = 0;
const collection = db.collection.bind(db);
db.collection = (path) => {
  const ref = collection(path);
  ref.add ??= async (data) => {
    const doc = ref.doc(`auto_${++autoId}`);
    await doc.set(data);
    return doc;
  };
  return ref;
};

const {reportUser} = require("../lib/social.js");
const {
  AUTO_HOLD_DISTINCT_REPORTERS,
  AUTO_HOLD_WINDOW_MS,
  decideAutoHold,
  distinctRecentReporters,
  reasonHoldsAtOnce,
} = require("../lib/admin/reports/reportAutoHold.js");
const {REPORT_PRIORITY} = require("../lib/admin/reports/reportPriority.js");

const REPORTED = "reported-1";
const REPORTERS = ["reporter-1", "reporter-2", "reporter-3", "reporter-4"];
const NON_CRITICAL = Object.keys(REPORT_PRIORITY).filter((reason) => REPORT_PRIORITY[reason] !== "critical");

function seedWorld() {
  autoId = 0;
  const docs = {
    [`users/${REPORTED}`]: {uid: REPORTED, accountStatus: "active"},
    [`profiles/${REPORTED}`]: {
      uid: REPORTED,
      displayName: "Reported",
      isDiscoverable: true,
      profileModerationStatus: "approved",
      photos: [
        {id: "p1", moderationStatus: "approved", order: 0},
        {id: "p2", moderationStatus: "approved", order: 1},
        {id: "p3", moderationStatus: "rejected", order: 2},
      ],
    },
  };
  for (const uid of REPORTERS) {
    docs[`users/${uid}`] = {uid, accountStatus: "active"};
  }
  db.reset(docs);
}

async function report(reporter, reason) {
  return callAs(reportUser, reporter, {userId: REPORTED, reason});
}

async function world() {
  const reports = (await db.collection("reports").get()).docs.map((doc) => ({id: doc.id, ...doc.data()}));
  const cases = (await db.collection("moderationCases").get()).docs.map((doc) => ({id: doc.id, ...doc.data()}));
  const profile = (await db.doc(`profiles/${REPORTED}`).get()).data();
  return {reports, cases, profile};
}

function photoStatuses(profile) {
  return profile.photos.map((photo) => photo.moderationStatus);
}

const UNTOUCHED = ["approved", "approved", "rejected"];
const HELD = ["manual_review", "manual_review", "rejected"];

beforeEach(seedWorld);

describe("which reasons hold at once", () => {
  it("are exactly the critical ones", () => {
    assert.equal(reasonHoldsAtOnce("child_safety"), true);
    assert.equal(reasonHoldsAtOnce("underage"), true);
    for (const reason of NON_CRITICAL) {
      assert.equal(reasonHoldsAtOnce(reason), false, reason);
    }
    // A reason that is not on the whitelist never holds on its own.
    assert.equal(reasonHoldsAtOnce("admin_override"), false);
    assert.equal(reasonHoldsAtOnce(""), false);
  });

  it("the threshold is three members inside thirty days", () => {
    assert.equal(AUTO_HOLD_DISTINCT_REPORTERS, 3);
    assert.equal(AUTO_HOLD_WINDOW_MS, 30 * 24 * 60 * 60 * 1000);
  });
});

describe("a single report", () => {
  for (const reason of NON_CRITICAL) {
    it(`for ${reason} is queued but leaves the photos alone`, async () => {
      assert.deepEqual(await report(REPORTERS[0], reason), {ok: true});

      const {reports, cases, profile} = await world();
      // The report and its case exist exactly as before…
      assert.equal(reports.length, 1);
      assert.equal(reports[0].status, "open");
      assert.equal(reports[0].reason, reason);
      assert.equal(cases.length, 1);
      assert.equal(reports[0].caseId, cases[0].id);
      // …but the member is not taken out of circulation by one person.
      assert.equal(profile.profileModerationStatus, "approved");
      assert.deepEqual(photoStatuses(profile), UNTOUCHED);
    });
  }

  for (const reason of ["child_safety", "underage"]) {
    it(`for ${reason} holds the photos at once`, async () => {
      await report(REPORTERS[0], reason);

      const {profile} = await world();
      assert.equal(profile.profileModerationStatus, "manual_review");
      assert.deepEqual(photoStatuses(profile), HELD);
      assert.equal(profile.photos[0].moderationReason, `report:${reason}`);
    });
  }
});

describe("several reports about one member", () => {
  it("two different members are not enough", async () => {
    await report(REPORTERS[0], "harassment");
    await report(REPORTERS[1], "spam");

    const {reports, profile} = await world();
    assert.equal(reports.length, 2);
    assert.deepEqual(photoStatuses(profile), UNTOUCHED);
  });

  it("the third different member holds the photos", async () => {
    await report(REPORTERS[0], "harassment");
    await report(REPORTERS[1], "spam");
    await report(REPORTERS[2], "fake_profile");

    const {profile} = await world();
    assert.equal(profile.profileModerationStatus, "manual_review");
    assert.deepEqual(photoStatuses(profile), HELD);
    // The hold carries the reason of the report that tipped it.
    assert.equal(profile.photos[0].moderationReason, "report:fake_profile");
    assert.equal(profile.photos[0].moderatedBy, "report-pipeline");
  });

  it("one member reporting again and again counts once", async () => {
    await report(REPORTERS[0], "harassment");
    await report(REPORTERS[0], "spam");
    await report(REPORTERS[0], "scam");
    await report(REPORTERS[1], "harassment");

    const {reports, profile} = await world();
    assert.equal(reports.length, 4);
    assert.deepEqual(photoStatuses(profile), UNTOUCHED);
  });

  it("reports staff have closed no longer count", async () => {
    await report(REPORTERS[0], "harassment");
    await report(REPORTERS[1], "harassment");
    for (const doc of (await db.collection("reports").get()).docs) {
      await db.doc(`reports/${doc.id}`).set({status: "resolved"}, {merge: true});
    }

    await report(REPORTERS[2], "harassment");

    const {profile} = await world();
    assert.deepEqual(photoStatuses(profile), UNTOUCHED);
  });

  it("a critical report holds even when it is the first", async () => {
    await report(REPORTERS[0], "spam");
    await report(REPORTERS[1], "underage");

    const {profile} = await world();
    assert.deepEqual(photoStatuses(profile), HELD);
    assert.equal(profile.photos[0].moderationReason, "report:underage");
  });
});

describe("the thirty-day window", () => {
  const now = Date.UTC(2026, 9, 2, 12);
  const daysAgo = (days) => new Date(now - days * 24 * 60 * 60 * 1000);

  it("counts a report from yesterday and drops one from five weeks ago", () => {
    const reporters = distinctRecentReporters(
      [
        {reporterId: "a", createdAt: daysAgo(1)},
        {reporterId: "b", createdAt: daysAgo(35)},
        {reporterId: "c", createdAt: {toMillis: () => now - 29 * 24 * 60 * 60 * 1000}},
        {reporterId: "", createdAt: daysAgo(1)},
      ],
      now,
    );

    assert.deepEqual([...reporters].sort(), ["a", "c"]);
  });

  it("counts a report whose server time has not resolved yet", () => {
    const reporters = distinctRecentReporters([{reporterId: "a", createdAt: null}], now);

    assert.deepEqual([...reporters], ["a"]);
  });

  it("old reports do not add up to a hold", async () => {
    await db.doc("reports/old-1").set({
      reporterId: REPORTERS[0], reportedUserId: REPORTED, reason: "spam", status: "open", createdAt: daysAgo(40),
    });
    await db.doc("reports/old-2").set({
      reporterId: REPORTERS[1], reportedUserId: REPORTED, reason: "spam", status: "open", createdAt: daysAgo(31),
    });

    const decision = await decideAutoHold(
      db,
      {reporterId: REPORTERS[2], reportedUserId: REPORTED, reason: "spam"},
      now,
    );

    assert.deepEqual(decision, {hold: false, cause: null, distinctReporters: 1});
  });

  it("recent reports from two others plus this one do", async () => {
    await db.doc("reports/new-1").set({
      reporterId: REPORTERS[0], reportedUserId: REPORTED, reason: "spam", status: "open", createdAt: daysAgo(20),
    });
    await db.doc("reports/new-2").set({
      reporterId: REPORTERS[1], reportedUserId: REPORTED, reason: "scam", status: "open", createdAt: daysAgo(2),
    });
    // A report about someone else never counts.
    await db.doc("reports/other").set({
      reporterId: REPORTERS[3], reportedUserId: "someone-else", reason: "spam", status: "open", createdAt: daysAgo(1),
    });

    const decision = await decideAutoHold(
      db,
      {reporterId: REPORTERS[2], reportedUserId: REPORTED, reason: "harassment"},
      now,
    );

    assert.deepEqual(decision, {hold: true, cause: "reporter_threshold", distinctReporters: 3});
  });
});
