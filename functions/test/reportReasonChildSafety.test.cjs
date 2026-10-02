const {beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

/**
 * Members can report a child-safety concern (sexual content or behaviour
 * involving a minor) as its own reason, `child_safety`.
 *
 * The reason has to be more than a new string in a list: it must be accepted
 * by reportUser, land at the top of the moderation queue, open its own case,
 * and set off exactly the protective steps an `underage` report sets off. It
 * must never fall through a default branch to the priority of an unknown
 * reason. reportUser runs here end to end against the in-memory Firestore.
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
  REPORT_PRIORITY,
  REPORT_REASONS,
  reportCorrelationKey,
  reportPriority,
} = require("../lib/admin/reports/reportPriority.js");
const {PRIORITY_RANK} = require("../lib/admin/cases/caseTypes.js");

const REPORTER = "reporter-1";
const REPORTED = "reported-1";

function seedWorld() {
  autoId = 0;
  db.reset({
    [`users/${REPORTER}`]: {uid: REPORTER, accountStatus: "active"},
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
  });
}

async function fileReport(reason, extra = {}) {
  const result = await callAs(reportUser, REPORTER, {userId: REPORTED, reason, ...extra});
  const reports = (await db.collection("reports").get()).docs.map((doc) => ({id: doc.id, ...doc.data()}));
  const cases = (await db.collection("moderationCases").get()).docs.map((doc) => ({id: doc.id, ...doc.data()}));
  const profile = (await db.doc(`profiles/${REPORTED}`).get()).data();
  return {result, reports, cases, profile};
}

/** The parts of a report's outcome that must not depend on which critical reason was chosen. */
function protectiveOutcome({reports, cases, profile}, reason) {
  const [report] = reports;
  const [moderationCase] = cases;
  return {
    reportStatus: report.status,
    reportPriority: report.priority,
    reportPriorityRank: report.priorityRank,
    reportLinkedToCase: report.caseId === moderationCase.id,
    caseType: moderationCase.type,
    caseStatus: moderationCase.status,
    casePriority: moderationCase.priority,
    caseSubject: moderationCase.subjectUserId,
    caseCarriesReason: (moderationCase.reasonCodes ?? []).includes(reason),
    profileModerationStatus: profile.profileModerationStatus,
    photoStatuses: profile.photos.map((photo) => photo.moderationStatus),
    photosFlaggedByReport: profile.photos
      .filter((photo) => photo.moderationStatus === "manual_review")
      .every((photo) => photo.moderationReason === `report:${reason}` && photo.moderatedBy === "report-pipeline"),
  };
}

beforeEach(seedWorld);

describe("child_safety is a production report reason", () => {
  it("is on the server whitelist, next to underage", () => {
    assert.equal(REPORT_REASONS.has("child_safety"), true);
    assert.equal(REPORT_REASONS.has("underage"), true);
  });

  it("is the highest priority, never the default of an unknown reason", () => {
    const childSafety = reportPriority("child_safety");
    assert.equal(childSafety.priority, "critical");
    assert.equal(childSafety.priorityRank, PRIORITY_RANK.critical);
    assert.equal(childSafety.priorityRank, Math.max(...Object.values(PRIORITY_RANK)));
    assert.ok(childSafety.priorityRank >= reportPriority("underage").priorityRank);
    // What an unrecognised reason gets; child_safety must not share it.
    assert.equal(reportPriority("made-up").priority, "normal");
    assert.notEqual(childSafety.priority, reportPriority("made-up").priority);
  });

  it("every accepted reason has an explicit priority, and nothing else does", () => {
    assert.deepEqual([...REPORT_REASONS].sort(), Object.keys(REPORT_PRIORITY).sort());
    for (const reason of REPORT_REASONS) {
      assert.ok(Object.hasOwn(REPORT_PRIORITY, reason), `${reason} would fall through to the default`);
    }
    assert.deepEqual([...REPORT_REASONS].sort(), [
      "child_safety",
      "fake_profile",
      "harassment",
      "inappropriate_content",
      "other",
      "scam",
      "spam",
      "underage",
    ]);
  });

  it("opens its own case, never merged into an underage or spam case", () => {
    const keys = new Set(["child_safety", "underage", "spam"].map((reason) => reportCorrelationKey(REPORTED, reason)));
    assert.equal(keys.size, 3);
  });
});

describe("reportUser accepts child_safety", () => {
  it("stores the report as critical and returns ok", async () => {
    const {result, reports} = await fileReport("child_safety", {
      matchId: "m1",
      messageId: "msg1",
      description: "sent sexual messages about a minor",
    });

    assert.deepEqual(result, {ok: true});
    assert.equal(reports.length, 1);
    const [report] = reports;
    assert.equal(report.reason, "child_safety");
    assert.equal(report.reporterId, REPORTER);
    assert.equal(report.reportedUserId, REPORTED);
    assert.equal(report.priority, "critical");
    assert.equal(report.priorityRank, PRIORITY_RANK.critical);
    assert.equal(report.status, "open");
    assert.equal(report.matchId, "m1");
    assert.equal(report.messageId, "msg1");
    assert.equal(report.description, "sent sexual messages about a minor");
  });

  it("ignores a priority supplied by the client", async () => {
    const {reports} = await fileReport("child_safety", {priority: "low", priorityRank: 0});
    assert.equal(reports[0].priority, "critical");
    assert.equal(reports[0].priorityRank, PRIORITY_RANK.critical);
  });

  it("opens a critical USER_REPORT case that carries the reason", async () => {
    const {reports, cases} = await fileReport("child_safety");

    assert.equal(cases.length, 1);
    const [moderationCase] = cases;
    assert.equal(moderationCase.type, "USER_REPORT");
    assert.equal(moderationCase.priority, "critical");
    assert.equal(moderationCase.subjectUserId, REPORTED);
    assert.deepEqual(moderationCase.reasonCodes, ["child_safety"]);
    assert.deepEqual(moderationCase.sourceRefs, [`reports/${reports[0].id}`]);
    assert.equal(reports[0].caseId, moderationCase.id);
  });

  it("sends the reported member's photos and profile to manual review", async () => {
    const {profile} = await fileReport("child_safety");

    assert.equal(profile.profileModerationStatus, "manual_review");
    assert.deepEqual(
      profile.photos.map((photo) => [photo.id, photo.moderationStatus]),
      [["p1", "manual_review"], ["p2", "manual_review"], ["p3", "rejected"]],
    );
    assert.equal(profile.photos[0].moderationReason, "report:child_safety");
    assert.equal(profile.photos[0].moderatedBy, "report-pipeline");
  });

  it("triggers exactly the protective behaviour an underage report triggers", async () => {
    const underage = protectiveOutcome(await fileReport("underage"), "underage");
    seedWorld();
    const childSafety = protectiveOutcome(await fileReport("child_safety"), "child_safety");

    assert.deepEqual(childSafety, underage);
    // And that behaviour is the strict one, not a shared no-op.
    assert.equal(childSafety.reportPriority, "critical");
    assert.equal(childSafety.casePriority, "critical");
    assert.equal(childSafety.profileModerationStatus, "manual_review");
    assert.equal(childSafety.caseCarriesReason, true);
    assert.equal(childSafety.photosFlaggedByReport, true);
  });

  it("keeps a child_safety report apart from an underage one about the same member", async () => {
    await fileReport("underage");
    const {reports, cases} = await fileReport("child_safety");

    assert.equal(reports.length, 2);
    assert.equal(cases.length, 2);
    assert.deepEqual(cases.map((c) => c.priority), ["critical", "critical"]);
    assert.deepEqual(cases.flatMap((c) => c.reasonCodes).sort(), ["child_safety", "underage"]);
  });

  it("still refuses reasons that are not on the whitelist", async () => {
    for (const reason of ["childSafety", "CHILD_SAFETY", "child-safety", "csae", "admin_override", ""]) {
      await assert.rejects(callAs(reportUser, REPORTER, {userId: REPORTED, reason}), (error) => {
        assert.equal(error.code, "invalid-argument");
        assert.equal(error.message, "invalid-reason");
        return true;
      });
    }
    assert.equal((await db.collection("reports").get()).size, 0);
  });
});
