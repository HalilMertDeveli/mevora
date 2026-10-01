const {beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

// deleteAccount.js binds getFirestore()/getAuth() at load, so the in-memory
// doubles go in first. deleteAuthUserIfPresent below takes its own client.
const db = createFakeFirestore();
const {auth} = installFirebaseAdminStubs({db});
const {deleteAuthUserIfPresent, deleteUserAccount} = require("../lib/deleteAccount.js");
const {verifyAccountDeletion} = require("../lib/automation/deletionVerify.js");

/**
 * Deletion has to survive being asked twice.
 *
 * `deleteUserAccount` used to end with a bare `auth.deleteUser(uid)`. On a
 * retry — a double tap, a network retry, an app resume — the Auth record was
 * already gone, `auth/user-not-found` went unhandled, and the client got
 * 500 INTERNAL *after* the account had in fact been deleted. Every Firestore
 * step in that function is idempotent; the Auth step now is too.
 */
function authThatThrows(code) {
  return {
    calls: 0,
    async deleteUser() {
      this.calls += 1;
      const error = new Error("auth failure");
      error.code = code;
      throw error;
    },
  };
}

describe("account deletion is idempotent", () => {
  it("deletes the Auth record on the first attempt", async () => {
    const deleted = [];
    const client = {deleteUser: async (uid) => void deleted.push(uid)};

    await deleteAuthUserIfPresent(client, "uid-a");

    assert.deepEqual(deleted, ["uid-a"]);
  });

  it("treats an already-deleted Auth record as success", async () => {
    // The regression: this used to surface as 500 INTERNAL on a retry.
    const client = authThatThrows("auth/user-not-found");

    await assert.doesNotReject(() => deleteAuthUserIfPresent(client, "uid-a"));
    assert.equal(client.calls, 1);
  });

  it("still fails loudly on any other Auth error", async () => {
    // Swallowing everything would hide a real failure and leave a live account
    // behind while reporting success.
    for (const code of [
      "auth/internal-error",
      "auth/insufficient-permission",
      "auth/network-error",
      undefined,
    ]) {
      const client = authThatThrows(code);
      await assert.rejects(
        () => deleteAuthUserIfPresent(client, "uid-a"),
        (error) => error.message === "auth failure",
        `expected ${String(code)} to propagate`,
      );
    }
  });

  it("can be called repeatedly without throwing", async () => {
    let live = true;
    const client = {
      async deleteUser() {
        if (!live) {
          const error = new Error("gone");
          error.code = "auth/user-not-found";
          throw error;
        }
        live = false;
      },
    };

    await deleteAuthUserIfPresent(client, "uid-a");
    await deleteAuthUserIfPresent(client, "uid-a");
    await deleteAuthUserIfPresent(client, "uid-a");

    assert.equal(live, false);
  });
});

/**
 * Humor data is an inferred personality profile plus a trail of reports that
 * name the reporter. Account deletion has to take all of it, and the
 * post-deletion verification has to notice if any of it survives.
 */
describe("account deletion erases humor data", () => {
  const UID = "uid-humor";
  const OTHER = "uid-other";

  function seedHumorUser() {
    db.reset({
      [`users/${UID}`]: {uid: UID},
      [`profiles/${UID}`]: {uid: UID},
      [`users/${UID}/humor/summary`]: {vector: {sarcasm: 80}, interactionCount: 15},
      [`users/${UID}/humor/calibration`]: {version: 1, completedCount: 15, complete: true},
      [`users/${UID}/humor/core`]: {schemaVersion: 1, answers: {c1: {rating: "funny", dayId: "2026-09-28"}},
        today: {dayId: "2026-09-29", contentIds: ["c1"], kind: "core"}},
      [`users/${UID}/humorInteractions/c1`]: {contentId: "c1", rating: "funny"},
      [`users/${UID}/humorInteractions/c2`]: {contentId: "c2", reported: true, skipped: true},
      [`users/${UID}/humorDaily/2026-09-28`]: {dayId: "2026-09-28", answeredCount: 10, completed: true,
        answers: {"0": {contentId: "c1", rating: "funny", skipped: false}}},
      [`users/${UID}/humorDaily/2026-09-29`]: {dayId: "2026-09-29", answeredCount: 3, completed: false},
      "humorDailySets/2026-09-29": {dayId: "2026-09-29", status: "published", version: 1, contentIds: ["c1"]},
      [`humorReports/${UID}_c1`]: {reporterId: UID, contentId: "c1", details: "mine", status: "open"},
      [`humorReports/${UID}_c2`]: {reporterId: UID, contentId: "c2", status: "resolved"},
      [`humorReports/${OTHER}_c1`]: {reporterId: OTHER, contentId: "c1", status: "open"},
      "humorModerationQueue/c1": {contentId: "c1", status: "needs_review", reportCount: 2, lastReporterId: UID},
      "humorModerationQueue/c3": {contentId: "c3", status: "needs_review", reportCount: 1, lastReporterId: OTHER},
      "humorContent/c1": {contentId: "c1", active: true, safetyStatus: "approved"},
      [`users/${OTHER}/humor/summary`]: {vector: {dry: 70}, interactionCount: 20},
    });
    auth.users.clear();
    auth.addUser(UID);
    auth.addUser(OTHER);
  }

  beforeEach(seedHumorUser);

  it("leaves no humor summary, calibration, interaction or report of the user", async () => {
    const result = await callAs(deleteUserAccount, UID);
    assert.equal(result.ok, true);

    const remaining = db.paths();
    for (const path of remaining) {
      assert.equal(path.startsWith(`users/${UID}/`), false, `left behind: ${path}`);
      assert.equal(path.startsWith(`humorReports/${UID}_`), false, `left behind: ${path}`);
    }
    for (const path of remaining.filter((p) => p.startsWith("humorReports/"))) {
      assert.notEqual(db.read(path).reporterId, UID, `report still names the user: ${path}`);
    }
    for (const path of remaining.filter((p) => p.startsWith("humorModerationQueue/"))) {
      assert.notEqual(db.read(path).lastReporterId, UID, `queue still names the user: ${path}`);
    }
  });

  it("keeps other users' humor data and the content's moderation state", async () => {
    await callAs(deleteUserAccount, UID);

    assert.equal(db.read(`humorReports/${OTHER}_c1`).reporterId, OTHER);
    assert.equal(db.read(`users/${OTHER}/humor/summary`).interactionCount, 20);
    const queue = db.read("humorModerationQueue/c1");
    assert.equal("lastReporterId" in queue, false);
    assert.equal(queue.status, "needs_review");
    assert.equal(queue.reportCount, 2);
    assert.equal(db.read("humorModerationQueue/c3").lastReporterId, OTHER);
    assert.equal(db.read("humorContent/c1").active, true);
    // The global daily manifest holds no member data and outlives any account.
    assert.deepEqual(db.read("humorDailySets/2026-09-29").contentIds, ["c1"]);
  });

  it("verification passes after a real deletion and a retry", async () => {
    await callAs(deleteUserAccount, UID);
    await callAs(deleteUserAccount, UID);
    const verified = await verifyAccountDeletion(UID, db);
    assert.deepEqual(verified.issues, []);
    assert.equal(verified.complete, true);
  });

  it("verification reports every humor remnant", async () => {
    // What an in-flight humor call racing the deletion could leave behind.
    db.reset({
      [`users/${UID}/humor/summary`]: {vector: {sarcasm: 80}},
      [`users/${UID}/humor/calibration`]: {completedCount: 3},
      [`users/${UID}/humor/core`]: {answers: {c9: {rating: "funny"}}},
      [`users/${UID}/humorInteractions/c9`]: {contentId: "c9", rating: "funny"},
      [`users/${UID}/humorDaily/2026-09-29`]: {dayId: "2026-09-29", answeredCount: 1},
      [`humorReports/${UID}_c9`]: {reporterId: UID, contentId: "c9"},
      "humorModerationQueue/c9": {contentId: "c9", lastReporterId: UID},
    });
    auth.users.clear();
    const verified = await verifyAccountDeletion(UID, db);
    assert.equal(verified.complete, false);
    for (const issue of [
      `firestore_remnant:users/${UID}/humor/summary`,
      `firestore_remnant:users/${UID}/humor/calibration`,
      `firestore_remnant:users/${UID}/humor/core`,
      "humor_interactions_remnant",
      "humor_daily_remnant",
      "humor_reports_remnant",
      "humor_queue_reporter_remnant",
    ]) {
      assert.ok(verified.issues.includes(issue), `missing ${issue} in ${verified.issues}`);
    }
  });
});
