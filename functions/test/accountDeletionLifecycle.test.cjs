const {describe, it} = require("node:test");
const assert = require("node:assert/strict");

const {
  anonymizeDeletedUserMessages,
  clearLastMessagePreviewIfAuthored,
  deleteSupportAttachmentsForUser,
  deleteUserScopedRemnants,
  flagModerationRecordsForDeletedUser,
} = require("../lib/automation/accountDataCleanup.js");
const {verifyAccountDeletion} = require("../lib/automation/deletionVerify.js");
const {processJobById} = require("../lib/automation/runner.js");
const {rearmTerminalJob} = require("../lib/automation/jobs.js");
const {JobKind, JobStatus} = require("../lib/automation/types.js");

/**
 * In-memory Firestore double: flat path -> data map, with the subset of the API
 * the deletion path uses (doc/collection/where/orderBy/limit/batch/transaction).
 */
function fakeDb(seed = {}) {
  const store = new Map(Object.entries(seed));

  const parentOf = (docPath) => docPath.slice(0, docPath.lastIndexOf("/"));

  const snapshotOf = (docPath) => {
    const data = store.get(docPath);
    return {
      id: docPath.split("/").pop(),
      exists: data !== undefined,
      ref: makeRef(docPath),
      data: () => data,
      get: (field) => (data === undefined ? undefined : data[field]),
    };
  };

  function matches(data, clauses) {
    return clauses.every(([field, op, value]) => {
      const actual = data[field];
      if (op === "==") return actual === value;
      if (op === "array-contains") return Array.isArray(actual) && actual.includes(value);
      throw new Error(`unsupported operator: ${op}`);
    });
  }

  function makeQuery(collectionPath, clauses = [], limit = null, order = null) {
    const self = {
      where: (field, op, value) =>
        makeQuery(collectionPath, [...clauses, [field, op, value]], limit, order),
      limit: (n) => makeQuery(collectionPath, clauses, n, order),
      orderBy: (field, direction = "asc") =>
        makeQuery(collectionPath, clauses, limit, {field, direction}),
      async get() {
        let paths = [...store.keys()].filter((p) => parentOf(p) === collectionPath);
        paths = paths.filter((p) => matches(store.get(p), clauses));
        if (order) {
          paths.sort((a, b) => {
            const av = store.get(a)[order.field];
            const bv = store.get(b)[order.field];
            const cmp = av < bv ? -1 : av > bv ? 1 : 0;
            return order.direction === "desc" ? -cmp : cmp;
          });
        } else {
          paths.sort();
        }
        if (limit !== null) paths = paths.slice(0, limit);
        const docs = paths.map(snapshotOf);
        return {docs, size: docs.length, empty: docs.length === 0};
      },
      doc: (id) => makeRef(`${collectionPath}/${id}`),
    };
    return self;
  }

  function makeRef(docPath) {
    return {
      path: docPath,
      id: docPath.split("/").pop(),
      async get() {
        return snapshotOf(docPath);
      },
      async set(patch, options) {
        const prev = options && options.merge ? store.get(docPath) || {} : {};
        store.set(docPath, {...prev, ...patch});
      },
      async delete() {
        store.delete(docPath);
      },
      collection: (name) => makeQuery(`${docPath}/${name}`),
    };
  }

  return {
    store,
    doc: makeRef,
    collection: (name) => makeQuery(name),
    batch() {
      const ops = [];
      return {
        set: (ref, patch, options) => ops.push(() => ref.set(patch, options)),
        delete: (ref) => ops.push(() => ref.delete()),
        async commit() {
          for (const op of ops) await op();
        },
      };
    },
    async runTransaction(fn) {
      return fn({
        get: async (ref) => ref.get(),
        update: (ref, patch) => {
          store.set(ref.path, {...(store.get(ref.path) || {}), ...patch});
        },
      });
    },
  };
}

/** Storage double that records deletions and can list by prefix. */
function fakeBucket(objects = []) {
  const live = new Set(objects);
  return {
    live,
    file: (path) => ({
      async delete() {
        live.delete(path);
      },
    }),
    async deleteFiles({prefix}) {
      for (const path of [...live]) {
        if (path.startsWith(prefix)) live.delete(path);
      }
    },
    hasPrefix: (prefix) => [...live].some((p) => p.startsWith(prefix)),
  };
}

/** Auth and Storage both report the account fully removed. */
const cleanDeps = {
  authUserExists: async () => false,
  prefixHasObjects: async () => false,
};

const A = "userA";
const B = "userB";

/** A matched pair with messages from both sides. */
function seedSharedMatch() {
  return {
    "matches/m1": {userIds: [A, B], isActive: true, lastMessage: "see you then"},
    "matches/m1/messages/msg1": {
      senderId: A, receiverId: B, text: "hi from A", type: "text",
      createdAt: 100, imageStoragePath: "users/userA/chat/m1/a.bin",
    },
    "matches/m1/messages/msg2": {
      senderId: B, receiverId: A, text: "hi from B", type: "text", createdAt: 200,
    },
    "matches/m1/messages/msg3": {
      senderId: A, receiverId: B, text: "see you then", type: "text", createdAt: 300,
    },
  };
}

describe("DL-2 — shared conversation survives the peer's deletion", () => {
  it("erases only the departing user's messages", async () => {
    const db = fakeDb(seedSharedMatch());
    const tombstoned = await anonymizeDeletedUserMessages(db, A, db.doc("matches/m1"));
    assert.equal(tombstoned, 2);

    for (const id of ["msg1", "msg3"]) {
      const msg = db.store.get(`matches/m1/messages/${id}`);
      assert.equal(msg.deleted, true, `${id} should be tombstoned`);
      assert.equal(msg.text, "");
      assert.equal(msg.imageStoragePath, null);
      assert.equal(msg.senderId, A, "sender is retained so rules still resolve the thread");
    }

    // The regression this guards: the peer's own history used to be deleted too.
    const peer = db.store.get("matches/m1/messages/msg2");
    assert.equal(peer.text, "hi from B");
    assert.notEqual(peer.deleted, true);
  });

  it("is idempotent across repeated deletion passes", async () => {
    const db = fakeDb(seedSharedMatch());
    await anonymizeDeletedUserMessages(db, A, db.doc("matches/m1"));
    const afterFirst = JSON.stringify(db.store.get("matches/m1/messages/msg2"));
    await anonymizeDeletedUserMessages(db, A, db.doc("matches/m1"));
    await anonymizeDeletedUserMessages(db, A, db.doc("matches/m1"));

    assert.equal(db.store.get("matches/m1/messages/msg1").deleted, true);
    assert.equal(JSON.stringify(db.store.get("matches/m1/messages/msg2")), afterFirst);
    assert.equal(db.store.size, Object.keys(seedSharedMatch()).length, "nothing removed");
  });

  it("clears the match preview only when the last message was the departing user's", async () => {
    const db = fakeDb(seedSharedMatch());
    assert.equal(await clearLastMessagePreviewIfAuthored(A, db.doc("matches/m1")), true);
    assert.equal(db.store.get("matches/m1").lastMessage, "");

    // Peer authored the newest message: their preview must survive.
    const other = fakeDb({
      "matches/m2": {userIds: [A, B], lastMessage: "from B"},
      "matches/m2/messages/x": {senderId: B, text: "from B", createdAt: 400},
    });
    assert.equal(await clearLastMessagePreviewIfAuthored(A, other.doc("matches/m2")), false);
    assert.equal(other.store.get("matches/m2").lastMessage, "from B");
  });
});

describe("DL-3 — moderation evidence outlives the account", () => {
  it("retains and flags reports instead of deleting them", async () => {
    const db = fakeDb({
      "reports/r1": {reporterId: B, reportedUserId: A, reason: "abuse", status: "open"},
      "reports/r2": {reporterId: A, reportedUserId: "userC", reason: "spam", status: "open"},
      "reports/r3": {reporterId: B, reportedUserId: "userC", reason: "spam", status: "open"},
      "humorReports/userA_c1": {reporterId: A, contentId: "c1", reason: "other"},
    });

    const counts = await flagModerationRecordsForDeletedUser(db, A);
    assert.deepEqual(counts, {reports: 2, humorReports: 1});

    // The regression: a reported user could erase the evidence trail by leaving.
    assert.ok(db.store.has("reports/r1"));
    assert.equal(db.store.get("reports/r1").reportedUserDeleted, true);
    assert.equal(db.store.get("reports/r1").reason, "abuse");

    // A report filed by the departing user is evidence about someone else.
    assert.ok(db.store.has("reports/r2"));
    assert.equal(db.store.get("reports/r2").reporterDeleted, true);

    // Unrelated reports are untouched.
    assert.equal(db.store.get("reports/r3").reporterDeleted, undefined);
    assert.equal(db.store.get("humorReports/userA_c1").reporterDeleted, true);
  });
});

describe("support attachment cleanup", () => {
  const seed = () => ({
    "supportTickets/t1": {userId: A, attachments: ["support/t1/a1.jpg"], subject: "s"},
    "supportTickets/t2": {userId: A, attachmentUrl: "support/t2/a2.png", attachments: []},
    "supportTickets/t9": {userId: B, attachments: ["support/t9/b1.jpg"], subject: "s"},
  });
  const objects = () => [
    "support/t1/a1.jpg",
    "support/t1/unrecorded.png",
    "support/t2/a2.png",
    "support/t9/b1.jpg",
  ];

  it("removes the deleting user's attachments and leaves another user's alone", async () => {
    const db = fakeDb(seed());
    const bucket = fakeBucket(objects());

    const result = await deleteSupportAttachmentsForUser(db, bucket, A);
    assert.deepEqual(result.ticketIds.sort(), ["t1", "t2"]);

    assert.equal(bucket.hasPrefix("support/t1/"), false);
    assert.equal(bucket.hasPrefix("support/t2/"), false);
    // The whole point of resolving ownership from Firestore rather than the path.
    assert.equal(bucket.live.has("support/t9/b1.jpg"), true);
  });

  it("sweeps uploads the ticket document never recorded", async () => {
    const db = fakeDb(seed());
    const bucket = fakeBucket(objects());
    await deleteSupportAttachmentsForUser(db, bucket, A);
    assert.equal(bucket.live.has("support/t1/unrecorded.png"), false);
  });

  it("does not fail when the attachments are already gone", async () => {
    const db = fakeDb(seed());
    const bucket = fakeBucket([]);
    const result = await deleteSupportAttachmentsForUser(db, bucket, A);
    assert.deepEqual(result.ticketIds.sort(), ["t1", "t2"]);
    assert.equal(result.objectsDeleted, 2);
  });
});

describe("user-scoped remnants", () => {
  it("removes the uid-keyed rate-limit document and tolerates a missing one", async () => {
    const db = fakeDb({"authRateLimits/spotify_userA": {count: 3}});
    await deleteUserScopedRemnants(db, A);
    assert.equal(db.store.has("authRateLimits/spotify_userA"), false);
    await deleteUserScopedRemnants(db, A);
  });
});

describe("accountDeletionVerify", () => {

  it("passes on a fully cleaned account and ignores intentional retention", async () => {
    // Match, peer message and moderation report are all retained by design.
    const db = fakeDb({
      "matches/m1": {userIds: [A, B], isActive: false},
      "matches/m1/messages/msg1": {senderId: A, deleted: true, text: ""},
      "matches/m1/messages/msg2": {senderId: B, text: "hi from B"},
      "reports/r1": {reporterId: B, reportedUserId: A, reportedUserDeleted: true},
    });
    const result = await verifyAccountDeletion(
      {uid: A, supportTicketIds: ["t1"]}, db, cleanDeps,
    );
    assert.deepEqual(result.issues, []);
    assert.equal(result.complete, true);
  });

  it("reports un-erased messages authored by the deleted user", async () => {
    const db = fakeDb({
      "matches/m1": {userIds: [A, B]},
      "matches/m1/messages/msg1": {senderId: A, text: "still here"},
    });
    const result = await verifyAccountDeletion({uid: A}, db, cleanDeps);
    assert.deepEqual(result.issues, ["message_content_remnant:m1"]);
    assert.equal(result.complete, false);
  });

  it("reports surviving documents, tickets and support attachments", async () => {
    const db = fakeDb({
      "users/userA": {uid: A},
      "authRateLimits/spotify_userA": {count: 1},
      "supportTickets/t1": {userId: A},
    });
    const result = await verifyAccountDeletion({uid: A, supportTicketIds: ["t1"]}, db, {
      authUserExists: async () => false,
      prefixHasObjects: async (prefix) => prefix === "support/t1/",
    });
    assert.ok(result.issues.includes("firestore_remnant:users/userA"));
    assert.ok(result.issues.includes("firestore_remnant:authRateLimits/spotify_userA"));
    assert.ok(result.issues.includes("support_ticket_remnant"));
    assert.ok(result.issues.includes("support_attachment_remnant:t1"));
    assert.equal(result.complete, false);
  });

  it("treats an Auth lookup failure as unverified, never as clean", async () => {
    const db = fakeDb({});
    const result = await verifyAccountDeletion({uid: A}, db, {
      authUserExists: async () => {
        throw new Error("network");
      },
      prefixHasObjects: async () => false,
    });
    assert.deepEqual(result.issues, ["auth_check_failed"]);
    assert.equal(result.complete, false);
  });

  it("reports a still-present Auth user", async () => {
    const result = await verifyAccountDeletion({uid: A}, fakeDb({}), {
      authUserExists: async () => true,
      prefixHasObjects: async () => false,
    });
    assert.deepEqual(result.issues, ["auth_user_still_exists"]);
  });
});

describe("verification job lifecycle", () => {
  const job = (overrides = {}) => ({
    "automationJobs/deletion_verify_userA": {
      kind: JobKind.accountDeletionVerify,
      status: JobStatus.queued,
      attempts: 0,
      maxAttempts: 5,
      idempotencyKey: "deletion_verify_userA",
      createdBy: "deleteUserAccount",
      payload: {uid: A, supportTicketIds: []},
      ...overrides,
    },
  });
  const ID = "deletion_verify_userA";

  it("runs queued -> processing -> succeeded on a clean deletion", async () => {
    // Retained-by-design records must not block the job from completing.
    const db = fakeDb({
      ...job(),
      "matches/m1": {userIds: [A, B], isActive: false},
      "matches/m1/messages/msg2": {senderId: B, text: "hi from B"},
      "reports/r1": {reporterId: B, reportedUserId: A, reportedUserDeleted: true},
    });
    const outcome = await processJobById(ID, db, cleanDeps);
    assert.equal(outcome.status, JobStatus.succeeded);

    const stored = db.store.get(`automationJobs/${ID}`);
    assert.equal(stored.status, JobStatus.succeeded);
    assert.equal(stored.attempts, 1);
    assert.equal(stored.result.complete, true);
    assert.deepEqual(stored.result.issues, []);
    assert.equal(stored.error, null);
  });

  it("runs queued -> processing -> manual_review when data survived", async () => {
    // users/userA present => incomplete deletion. Retrying cannot fix a
    // compliance gap, so it must surface for a human rather than churn.
    const db = fakeDb({...job(), "users/userA": {uid: A}});
    const outcome = await processJobById(ID, db, cleanDeps);
    assert.equal(outcome.processed, true);
    assert.equal(outcome.status, JobStatus.manual_review);

    const stored = db.store.get(`automationJobs/${ID}`);
    assert.equal(stored.status, JobStatus.manual_review);
    assert.equal(stored.attempts, 1, "the job was claimed, not left queued");
    assert.ok(stored.result.issues.includes("firestore_remnant:users/userA"));
  });

  it("does not leave a processed job queued", async () => {
    const db = fakeDb({...job(), "users/userA": {uid: A}});
    await processJobById(ID, db, cleanDeps);
    assert.notEqual(db.store.get(`automationJobs/${ID}`).status, JobStatus.queued);
  });

  it("re-arms a terminal job so a retried deletion is verified again", async () => {
    const db = fakeDb(job({status: JobStatus.succeeded, attempts: 1, result: {complete: true}}));
    const rearmed = await rearmTerminalJob(ID, {uid: A, supportTicketIds: ["t5"]}, db);
    assert.equal(rearmed, true);

    const stored = db.store.get(`automationJobs/${ID}`);
    assert.equal(stored.status, JobStatus.queued);
    assert.equal(stored.attempts, 0);
    assert.deepEqual(stored.payload.supportTicketIds, ["t5"]);
    assert.equal(stored.result, null, "the previous verdict must not be inherited");
  });

  it("leaves a job awaiting human review armed as-is", async () => {
    const db = fakeDb(job({status: JobStatus.manual_review}));
    assert.equal(await rearmTerminalJob(ID, {uid: A}, db), false);
    assert.equal(db.store.get(`automationJobs/${ID}`).status, JobStatus.manual_review);
  });

  it("bounds retries at maxAttempts", async () => {
    // A retryable failure on the final attempt must terminate, not retry forever.
    const db = fakeDb(job({kind: "not_a_real_kind", attempts: 4, maxAttempts: 5}));
    const outcome = await processJobById(ID, db, cleanDeps);
    assert.equal(outcome.status, JobStatus.failed);
    assert.equal(db.store.get(`automationJobs/${ID}`).nextRetryAt, null);
  });
});
