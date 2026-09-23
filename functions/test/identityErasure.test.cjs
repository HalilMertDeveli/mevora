const {describe, it, beforeEach, afterEach} = require("node:test");
const assert = require("node:assert/strict");

const {FieldValue} = require("firebase-admin/firestore");
const {
  requestIdentityProviderErasure,
  runIdentityErasureJob,
  IDENTITY_ERASURE_PENDING,
  applyIdentityProviderEvent,
} = require("../lib/identity/index.js");

const NOW = 1_800_000_000_000;
const realFetch = globalThis.fetch;

// Sentinels the double understands.
FieldValue.serverTimestamp = () => ({__ts: true});
FieldValue.delete = () => ({__delete: true});
FieldValue.increment = (n) => ({__increment: n});

function fakeDb(seed = {}) {
  const store = new Map(Object.entries(seed));
  const ref = (path) => ({
    path,
    get: async () => ({exists: store.has(path), data: () => store.get(path)}),
    set: async (value, options) => {
      const base = options && options.merge ? {...(store.get(path) ?? {})} : {};
      for (const [k, v] of Object.entries(value)) {
        if (v && v.__delete) delete base[k];
        else if (v && typeof v.__increment === "number") base[k] = (base[k] ?? 0) + v.__increment;
        else base[k] = v;
      }
      store.set(path, base);
    },
    delete: async () => {
      store.delete(path);
      return undefined;
    },
  });
  return {
    store,
    doc: ref,
    runTransaction: async (fn) => fn({
      get: (r) => r.get(),
      set: (r, value, options) => r.set(value, options),
    }),
  };
}

function mockFetch(handler) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({url: String(url), init});
    return handler(String(url), init ?? {});
  };
  return calls;
}

const response = (status, body = {}) => ({
  ok: status >= 200 && status < 300,
  status,
  json: async () => body,
  text: async () => JSON.stringify(body),
});

const pendingPath = (uid) => `${IDENTITY_ERASURE_PENDING}/${uid}`;

beforeEach(() => {
  process.env.DIDIT_API_KEY = "didit_test_api_key";
  process.env.DIDIT_WORKFLOW_ID = "wf_test";
  process.env.DIDIT_WEBHOOK_SECRET = "whsec_test";
  process.env.DIDIT_ENVIRONMENT = "sandbox";
});

afterEach(() => {
  globalThis.fetch = realFetch;
});

describe("provider erasure", () => {
  it("asks for privacy erasure, not an operational delete", async () => {
    const calls = mockFetch(async () => response(200, {
      session_id: "sess_1",
      face_retention_outcome: "deleted",
    }));
    const result = await requestIdentityProviderErasure(
      {uid: "uidA", providerSessionId: "sess_1"},
      fakeDb(),
    );

    assert.equal(result.confirmed, true);
    const [call] = calls;
    assert.equal(call.init.method, "DELETE");
    assert.match(call.url, /\/v3\/session\/sess_1\/delete\/$/);
    const body = JSON.parse(call.init.body);
    assert.equal(body.deletion_instruction, "privacy_erasure");
  });

  it("treats a 404 on a repeat call as erased, not as a failure", async () => {
    mockFetch(async () => response(404, {detail: "Not found."}));
    const db = fakeDb({[pendingPath("uidA")]: {providerSessionId: "sess_1"}});
    const result = await requestIdentityProviderErasure(
      {uid: "uidA", providerSessionId: "sess_1"},
      db,
    );

    assert.equal(result.confirmed, true);
    assert.equal(result.outcome, "alreadyAbsent");
    // The pending obligation is cleared, so the job stops retrying.
    assert.equal(db.store.has(pendingPath("uidA")), false);
  });

  it("records a pending obligation when the provider is unavailable", async () => {
    mockFetch(async () => response(503, {detail: "unavailable"}));
    const db = fakeDb();
    const result = await requestIdentityProviderErasure(
      {uid: "uidA", providerSessionId: "sess_1"},
      db,
    );

    assert.equal(result.confirmed, false);
    const pending = db.store.get(pendingPath("uidA"));
    assert.equal(pending.providerSessionId, "sess_1");
    assert.equal(pending.attempts, 1);
  });

  it("never claims erasure it was not told happened", async () => {
    for (const status of [400, 401, 403, 500, 503]) {
      mockFetch(async () => response(status, {}));
      const result = await requestIdentityProviderErasure(
        {uid: "uidA", providerSessionId: "sess_1"},
        fakeDb(),
      );
      assert.equal(result.confirmed, false, `status=${status}`);
    }
  });

  it("does not call the provider when no session was ever created", async () => {
    const calls = mockFetch(async () => response(200, {}));
    const db = fakeDb();
    const result = await requestIdentityProviderErasure({uid: "uidA"}, db);

    assert.equal(result.confirmed, true);
    assert.equal(result.outcome, "no_session");
    assert.equal(calls.length, 0);
    assert.equal(db.store.has(pendingPath("uidA")), false);
  });

  it("records the obligation rather than dropping it when unconfigured", async () => {
    delete process.env.DIDIT_API_KEY;
    delete process.env.DIDIT_WORKFLOW_ID;
    const db = fakeDb();
    const result = await requestIdentityProviderErasure(
      {uid: "uidA", providerSessionId: "sess_1"},
      db,
    );

    assert.equal(result.confirmed, false);
    assert.equal(result.outcome, "not_configured");
    assert.equal(db.store.get(pendingPath("uidA")).providerSessionId, "sess_1");
  });

  it("a network throw is a pending obligation, never a silent success", async () => {
    globalThis.fetch = async () => {
      throw new Error("ECONNRESET");
    };
    const db = fakeDb();
    const result = await requestIdentityProviderErasure(
      {uid: "uidA", providerSessionId: "sess_1"},
      db,
    );
    assert.equal(result.confirmed, false);
    assert.equal(db.store.has(pendingPath("uidA")), true);
  });

  it("stores no identity data in the pending record", async () => {
    mockFetch(async () => response(503, {}));
    const db = fakeDb();
    await requestIdentityProviderErasure({uid: "uidA", providerSessionId: "sess_1"}, db);

    assert.deepEqual(
      Object.keys(db.store.get(pendingPath("uidA"))).sort(),
      ["attempts", "createdAt", "lastAttemptAt", "lastOutcome", "provider", "providerSessionId", "uid"],
    );
  });
});

describe("erasure retry job", () => {
  it("retries a pending obligation and clears it on success", async () => {
    mockFetch(async () => response(200, {face_retention_outcome: "deleted"}));
    const db = fakeDb({[pendingPath("uidA")]: {uid: "uidA", providerSessionId: "sess_1", attempts: 1}});

    const result = await runIdentityErasureJob("uidA", db);
    assert.equal(result.complete, true);
    assert.equal(db.store.has(pendingPath("uidA")), false);
  });

  it("reports incomplete so the runner escalates instead of burying it", async () => {
    mockFetch(async () => response(503, {}));
    const db = fakeDb({[pendingPath("uidA")]: {uid: "uidA", providerSessionId: "sess_1", attempts: 1}});

    const result = await runIdentityErasureJob("uidA", db);
    assert.equal(result.complete, false);
    assert.equal(db.store.get(pendingPath("uidA")).attempts, 2);
  });

  it("is safe to run twice, and after the obligation is gone", async () => {
    mockFetch(async () => response(200, {}));
    const db = fakeDb({[pendingPath("uidA")]: {uid: "uidA", providerSessionId: "sess_1"}});

    assert.equal((await runIdentityErasureJob("uidA", db)).complete, true);
    const second = await runIdentityErasureJob("uidA", db);
    assert.equal(second.complete, true);
    assert.equal(second.outcome, "already_cleared");
  });
});

describe("late provider events after deletion", () => {
  const event = (over = {}) => ({
    eventId: "evt_late",
    uid: "uidA",
    providerSessionId: "sess_1",
    status: "verified",
    occurredAtMs: NOW,
    ...over,
  });

  it("does not recreate the user, the profile or the verification record", async () => {
    const db = fakeDb({});
    const result = await applyIdentityProviderEvent(db, event(), "didit");

    assert.equal(result.applied, false);
    assert.equal(result.skipped, "no_such_user");
    assert.equal(db.store.size, 0);
  });

  it("stays refused however many times it is redelivered", async () => {
    const db = fakeDb({});
    for (const eventId of ["evt_1", "evt_2", "evt_3"]) {
      const result = await applyIdentityProviderEvent(db, event({eventId}), "didit");
      assert.equal(result.applied, false);
      assert.equal(result.skipped, "no_such_user");
    }
    assert.equal(db.store.size, 0);
  });

  it("is refused for a declined outcome too, not just an approval", async () => {
    const db = fakeDb({});
    for (const status of ["verified", "declined", "expired", "in_review"]) {
      const result = await applyIdentityProviderEvent(db, event({status}), "didit");
      assert.equal(result.applied, false, `status=${status}`);
    }
    assert.equal(db.store.size, 0);
  });
});
