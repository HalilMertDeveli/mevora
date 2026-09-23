const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {processJobById} = require("../lib/automation/runner.js");
const {JobKind, JobStatus} = require("../lib/automation/types.js");

const SRC = path.join(__dirname, "..", "src");

/** Minimal in-memory Firestore double: doc get/set plus a real-ish transaction. */
function fakeDb(seed = {}) {
  const store = new Map(Object.entries(seed));
  const makeRef = (docPath) => ({
    path: docPath,
    async get() {
      const data = store.get(docPath);
      return {exists: data !== undefined, data: () => data, id: docPath.split("/").pop()};
    },
    async set(patch, options) {
      const prev = options && options.merge ? store.get(docPath) || {} : {};
      store.set(docPath, {...prev, ...patch});
    },
  });
  return {
    store,
    doc: (docPath) => makeRef(docPath),
    collection: (name) => ({
      doc: (id) => makeRef(`${name}/${id}`),
      where: () => ({limit: () => ({get: async () => ({empty: true, size: 0, docs: []})})}),
    }),
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

function seededJob(overrides = {}) {
  return {
    "automationJobs/job1": {
      kind: JobKind.accountDeletionVerify,
      status: JobStatus.queued,
      attempts: 0,
      maxAttempts: 5,
      idempotencyKey: "job1",
      createdBy: "deleteUserAccount",
      payload: {uid: "u1"},
      ...overrides,
    },
  };
}

describe("automation deletion runner", () => {
  it("is reachable from the deploy entrypoint", () => {
    // The regression: the handlers existed but index.ts never exported them, so
    // nothing was deployed to drain `automationJobs`.
    const index = fs.readFileSync(path.join(SRC, "index.ts"), "utf8");
    assert.match(index, /processAutomationTask/);
    assert.match(index, /automationJobDrain/);
    assert.match(index, /from "\.\/automation\/schedules\.js"/);
  });

  it("keeps the Cloud Tasks queue path aligned with the exported function name", () => {
    // enqueueCloudTask builds the queue path from a hardcoded function name; a
    // rename on either side silently drops every enqueued job.
    const enqueue = fs.readFileSync(
      path.join(SRC, "automation", "tasksEnqueue.ts"),
      "utf8",
    );
    const schedules = fs.readFileSync(
      path.join(SRC, "automation", "schedules.ts"),
      "utf8",
    );
    assert.match(enqueue, /functions\/processAutomationTask/);
    assert.match(schedules, /export const processAutomationTask/);
  });

  it("claims a queued job exactly once", async () => {
    // Payload omits uid so the handler fails fast and the test stays hermetic
    // (a real uid would reach Auth/Storage).
    const db = fakeDb(seededJob({payload: {}}));
    const first = await processJobById("job1", db);
    assert.equal(first.processed, true);
    assert.equal(first.status, JobStatus.failed);

    // Job left terminal, so a concurrent drain no-ops instead of re-running it.
    const second = await processJobById("job1", db);
    assert.deepEqual(second, {
      jobId: "job1",
      processed: false,
      reason: "not_claimable",
    });
  });

  it("records a missing uid as a terminal failure, not a retry", async () => {
    const db = fakeDb(seededJob({payload: {}}));
    const outcome = await processJobById("job1", db);
    assert.equal(outcome.processed, true);
    assert.equal(outcome.status, JobStatus.failed);
    const job = db.store.get("automationJobs/job1");
    assert.equal(job.error, "uid_required");
    assert.equal(job.attempts, 1);
    // A payload field cannot appear on retry, so the retry budget is not burned.
    assert.equal(job.nextRetryAt, null);
  });

  it("does not retry an unknown job kind", async () => {
    const db = fakeDb(seededJob({kind: "not_a_real_kind"}));
    const outcome = await processJobById("job1", db);
    assert.equal(outcome.status, JobStatus.failed);
    const job = db.store.get("automationJobs/job1");
    assert.match(job.error, /^unknown_job_kind:not_a_real_kind$/);
    assert.equal(job.nextRetryAt, null);
  });

  it("leaves a job that is not queued alone", async () => {
    const db = fakeDb(seededJob({status: JobStatus.succeeded}));
    const outcome = await processJobById("job1", db);
    assert.equal(outcome.processed, false);
  });

  it("skips jobs awaiting human review", async () => {
    const db = fakeDb(seededJob({requiresHumanReview: true}));
    const outcome = await processJobById("job1", db);
    assert.equal(outcome.processed, false);
  });
});
