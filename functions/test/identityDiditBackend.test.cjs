const {describe, it, beforeEach, afterEach} = require("node:test");
const assert = require("node:assert/strict");
const {createHmac} = require("node:crypto");
const {
  DiditApiError,
  DiditClient,
  DiditProvider,
  canonicalizeDiditPayload,
  isTimestampFresh,
  verifyDiditSignature,
  summarizeDecision,
  reasonForDecision,
  applyIdentityProviderEvent,
  reserveIdentitySessionAttempt,
  IdentityStartBlockedError,
  grantsVerifiedBadge,
} = require("../lib/identity/index.js");

const SECRET = "whsec_test_shared_key";
const API_KEY = "didit_test_api_key";
const NOW = 1_800_000_000_000; // fixed epoch ms
const nowSeconds = Math.floor(NOW / 1000);

function signedHeaders(body, {secret = SECRET, timestamp = nowSeconds} = {}) {
  const canonical = canonicalizeDiditPayload(JSON.parse(body));
  return {
    "x-signature-v2": createHmac("sha256", secret).update(canonical, "utf8").digest("hex"),
    "x-timestamp": String(timestamp),
  };
}

const approvedPayload = (over = {}) => JSON.stringify({
  event_id: "evt_1",
  webhook_type: "status.updated",
  session_id: "sess_1",
  vendor_data: "uidA",
  status: "Approved",
  timestamp: nowSeconds,
  environment: "sandbox",
  ...over,
});

// ---------------------------------------------------------------------------
// In-memory Firestore double: enough of the surface that the store's real
// transaction logic runs unchanged.
// ---------------------------------------------------------------------------
function fakeDb(seed = {}) {
  const store = new Map(Object.entries(seed));
  const ref = (path) => ({
    path,
    get: async () => ({
      exists: store.has(path),
      data: () => store.get(path),
    }),
    set: (value, options) => {
      const next = options && options.merge
        ? {...(store.get(path) ?? {}), ...value}
        : value;
      for (const [k, v] of Object.entries(next)) {
        if (v && v.__delete) delete next[k];
      }
      store.set(path, next);
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

// FieldValue sentinels are opaque objects at runtime; the double just stores
// them, except for delete() which it honours so `reason` clearing is testable.
const originalFieldValue = require("firebase-admin/firestore").FieldValue;
let patchedFieldValue = false;
beforeEach(() => {
  if (!patchedFieldValue) {
    originalFieldValue.serverTimestamp = () => ({__serverTimestamp: true});
    originalFieldValue.delete = () => ({__delete: true});
    patchedFieldValue = true;
  }
});
afterEach(() => {
  globalThis.fetch = realFetch;
});
const realFetch = globalThis.fetch;

function mockFetch(handler) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({url: String(url), init});
    return handler(String(url), init ?? {});
  };
  return calls;
}

const jsonResponse = (status, body) => ({
  ok: status >= 200 && status < 300,
  status,
  json: async () => body,
  text: async () => JSON.stringify(body),
});

const providerWith = (config = {}) => new DiditProvider(new DiditClient({
  apiKey: API_KEY,
  workflowId: "wf_test",
  baseUrl: "https://verification.didit.me",
  environment: "sandbox",
  ...config,
}));

// ---------------------------------------------------------------------------

describe("webhook signature canonicalization", () => {
  it("sorts keys recursively and stays compact", () => {
    const canonical = canonicalizeDiditPayload({
      b: 1,
      a: {d: [{z: 1, y: 2}], c: "x"},
    });
    assert.equal(canonical, '{"a":{"c":"x","d":[{"y":2,"z":1}]},"b":1}');
  });

  it("leaves non-ASCII unescaped", () => {
    assert.equal(canonicalizeDiditPayload({name: "Ayşe Öztürk"}), '{"name":"Ayşe Öztürk"}');
  });

  it("is stable regardless of how the provider ordered its keys", () => {
    const a = canonicalizeDiditPayload({status: "Approved", session_id: "s1"});
    const b = canonicalizeDiditPayload({session_id: "s1", status: "Approved"});
    assert.equal(a, b);
  });
});

describe("webhook authentication", () => {
  it("accepts a correctly signed body", () => {
    const body = approvedPayload();
    const result = verifyDiditSignature({secret: SECRET, rawBody: body, headers: signedHeaders(body)});
    assert.equal(result.valid, true);
    assert.equal(result.via, "v2");
  });

  it("survives a middleware that reordered the JSON keys", () => {
    const body = approvedPayload();
    const headers = signedHeaders(body);
    const reordered = JSON.stringify(
      Object.fromEntries(Object.entries(JSON.parse(body)).reverse()),
    );
    const result = verifyDiditSignature({secret: SECRET, rawBody: reordered, headers});
    assert.equal(result.valid, true);
  });

  it("rejects a body signed with the wrong secret", () => {
    const body = approvedPayload();
    const headers = signedHeaders(body, {secret: "attacker_secret"});
    const result = verifyDiditSignature({secret: SECRET, rawBody: body, headers});
    assert.equal(result.valid, false);
    assert.equal(result.reason, "invalid_signature");
  });

  it("rejects an unsigned body", () => {
    const result = verifyDiditSignature({
      secret: SECRET,
      rawBody: approvedPayload(),
      headers: {"x-timestamp": String(nowSeconds)},
    });
    assert.equal(result.valid, false);
    assert.equal(result.reason, "missing_signature");
  });

  it("rejects a tampered body under a valid signature", () => {
    const body = approvedPayload({status: "Declined"});
    const headers = signedHeaders(body);
    const tampered = approvedPayload({status: "Approved"});
    const result = verifyDiditSignature({secret: SECRET, rawBody: tampered, headers});
    assert.equal(result.valid, false);
  });

  it("does not accept the deprecated envelope-only signature", () => {
    const body = approvedPayload();
    const simple = createHmac("sha256", SECRET)
      .update(`${nowSeconds}:sess_1:Approved:status.updated`, "utf8")
      .digest("hex");
    const result = verifyDiditSignature({
      secret: SECRET,
      rawBody: body,
      headers: {"x-signature-simple": simple, "x-timestamp": String(nowSeconds)},
    });
    assert.equal(result.valid, false);
    assert.equal(result.reason, "missing_signature");
  });

  it("enforces the five-minute replay window", () => {
    assert.equal(isTimestampFresh(String(nowSeconds), NOW), true);
    assert.equal(isTimestampFresh(String(nowSeconds - 299), NOW), true);
    assert.equal(isTimestampFresh(String(nowSeconds - 301), NOW), false);
    assert.equal(isTimestampFresh(String(nowSeconds + 301), NOW), false);
    assert.equal(isTimestampFresh(undefined, NOW), false);
    assert.equal(isTimestampFresh("not-a-number", NOW), false);
  });
});

describe("webhook parsing", () => {
  const parse = (body, headers) =>
    providerWith().parseWebhookEvent({rawBody: body, headers, receivedAtMs: NOW});

  beforeEach(() => {
    process.env.DIDIT_WEBHOOK_SECRET = SECRET;
    process.env.DIDIT_API_KEY = API_KEY;
    process.env.DIDIT_WORKFLOW_ID = "wf_test";
  });

  it("reduces a signed event to what MEVORA acts on", () => {
    const body = approvedPayload();
    const event = parse(body, signedHeaders(body));
    assert.equal(event.uid, "uidA");
    assert.equal(event.providerSessionId, "sess_1");
    assert.equal(event.status, "verified");
    assert.equal(event.eventId, "evt_1");
    assert.equal(event.occurredAtMs, nowSeconds * 1000);
  });

  it("rejects a forged signature", () => {
    const body = approvedPayload();
    assert.throws(
      () => parse(body, signedHeaders(body, {secret: "nope"})),
      (e) => e.reason === "invalid_signature",
    );
  });

  it("rejects a replayed delivery", () => {
    const body = approvedPayload();
    assert.throws(
      () => parse(body, signedHeaders(body, {timestamp: nowSeconds - 600})),
      (e) => e.reason === "stale_timestamp",
    );
  });

  it("rejects a malformed body", () => {
    const raw = "{not json";
    const headers = {
      "x-signature-v2": "deadbeef",
      "x-timestamp": String(nowSeconds),
    };
    assert.throws(() => parse(raw, headers), (e) => e.reason === "malformed_body");
  });

  it("rejects an event with no uid to correlate against", () => {
    const body = approvedPayload({vendor_data: ""});
    assert.throws(
      () => parse(body, signedHeaders(body)),
      (e) => e.reason === "missing_correlation",
    );
  });

  it("refuses an event type MEVORA did not subscribe to", () => {
    const body = approvedPayload({webhook_type: "transaction.created"});
    assert.throws(
      () => parse(body, signedHeaders(body)),
      (e) => e.reason === "unknown_event",
    );
  });

  it("never reads an unknown provider status as verified", () => {
    for (const status of ["Something New", "approved", "APPROVED", 1, null]) {
      const body = approvedPayload({status});
      const event = parse(body, signedHeaders(body));
      assert.equal(grantsVerifiedBadge(event.status), false, `status=${status}`);
      assert.equal(event.status, "error");
    }
  });
});

describe("session creation", () => {
  it("sends the workflow id and the uid as vendor_data, with the key in a header", async () => {
    const calls = mockFetch(async () => jsonResponse(200, {
      session_id: "sess_9",
      session_token: "tok_9",
      url: "https://verify.example/s/9",
      status: "Not Started",
    }));
    const session = await providerWith().createSession({uid: "uidA", language: "tr"});

    assert.equal(session.providerSessionId, "sess_9");
    assert.equal(session.launchToken, "tok_9");
    assert.equal(session.status, "not_started");

    const [call] = calls;
    assert.match(call.url, /\/v3\/session\/$/);
    assert.equal(call.init.headers["x-api-key"], API_KEY);
    const body = JSON.parse(call.init.body);
    assert.equal(body.vendor_data, "uidA");
    assert.equal(body.workflow_id, "wf_test");
    assert.equal(body.language, "tr");
    // The API key must travel in the header, never in the body.
    assert.equal(JSON.stringify(body).includes(API_KEY), false);
  });

  it("surfaces a provider failure as a typed, retryable-aware error", async () => {
    mockFetch(async () => jsonResponse(503, {detail: "unavailable"}));
    await assert.rejects(
      () => providerWith().createSession({uid: "uidA"}),
      (e) => e instanceof DiditApiError && e.retryable === true,
    );
    mockFetch(async () => jsonResponse(400, {detail: "bad workflow"}));
    await assert.rejects(
      () => providerWith().createSession({uid: "uidA"}),
      (e) => e instanceof DiditApiError && e.retryable === false,
    );
  });

  it("refuses a response with no session id rather than inventing one", async () => {
    mockFetch(async () => jsonResponse(200, {session_token: "tok"}));
    await assert.rejects(
      () => providerWith().createSession({uid: "uidA"}),
      (e) => e.code === "didit-session-id-missing",
    );
  });
});

describe("attempt reservation", () => {
  const path = "users/uidA/verification/identity";

  it("moves a fresh user to pending and counts the attempt", async () => {
    const db = fakeDb({"users/uidA": {}});
    const result = await reserveIdentitySessionAttempt(db, "uidA", "didit", NOW);
    assert.deepEqual(result, {});
    assert.equal(db.store.get(path).status, "pending");
    assert.equal(db.store.get(path).attemptCount, 1);
  });

  it("hands back the in-flight session instead of creating a second one", async () => {
    const db = fakeDb({
      "users/uidA": {},
      [path]: {status: "pending", providerSessionId: "sess_1", attemptCount: 1},
    });
    const result = await reserveIdentitySessionAttempt(db, "uidA", "didit", NOW);
    assert.equal(result.resumableSessionId, "sess_1");
    // The attempt counter must not move for a resume.
    assert.equal(db.store.get(path).attemptCount, 1);
  });

  it("refuses a verified user", async () => {
    const db = fakeDb({"users/uidA": {}, [path]: {status: "verified"}});
    await assert.rejects(
      () => reserveIdentitySessionAttempt(db, "uidA", "didit", NOW),
      (e) => e instanceof IdentityStartBlockedError && e.reason === "already_verified",
    );
  });

  it("enforces the cooldown", async () => {
    const db = fakeDb({
      "users/uidA": {},
      [path]: {
        status: "declined",
        attemptCount: 1,
        lastAttemptAt: {toMillis: () => NOW - 60_000},
      },
    });
    await assert.rejects(
      () => reserveIdentitySessionAttempt(db, "uidA", "didit", NOW),
      (e) => e.reason === "cooldown",
    );
  });
});

describe("applying provider events", () => {
  const path = "users/uidA/verification/identity";
  const event = (over = {}) => ({
    eventId: "evt_1",
    uid: "uidA",
    providerSessionId: "sess_1",
    status: "verified",
    occurredAtMs: NOW,
    ...over,
  });

  it("verifies the user and sets both badges in one transaction", async () => {
    const db = fakeDb({"users/uidA": {isVerified: false}, "profiles/uidA": {}, [path]: {providerSessionId: "sess_1"}});
    const result = await applyIdentityProviderEvent(db, event(), "didit");
    assert.equal(result.applied, true);
    assert.equal(db.store.get(path).status, "verified");
    assert.equal(db.store.get("users/uidA").isVerified, true);
    // The public card carries the badge and nothing else.
    assert.equal(db.store.get("profiles/uidA").isVerified, true);
    assert.equal(db.store.get("profiles/uidA").providerSessionId, undefined);
    assert.equal(db.store.get("profiles/uidA").status, undefined);
    assert.equal(db.store.get("profiles/uidA").reason, undefined);
  });

  it("clears both badges on a terminal non-verified outcome", async () => {
    const db = fakeDb({"users/uidA": {isVerified: true}, "profiles/uidA": {isVerified: true}, [path]: {providerSessionId: "sess_1"}});
    await applyIdentityProviderEvent(db, event({status: "declined", reason: "face_mismatch"}), "didit");
    assert.equal(db.store.get(path).status, "declined");
    assert.equal(db.store.get(path).reason, "face_mismatch");
    assert.equal(db.store.get("users/uidA").isVerified, false);
    assert.equal(db.store.get("profiles/uidA").isVerified, false);
  });

  it("leaves an existing badge alone while a re-verification is in flight", async () => {
    const db = fakeDb({"users/uidA": {isVerified: true}, [path]: {providerSessionId: "sess_1"}});
    await applyIdentityProviderEvent(db, event({status: "in_review"}), "didit");
    assert.equal(db.store.get("users/uidA").isVerified, true);
  });

  it("ignores a redelivered event", async () => {
    const db = fakeDb({
      "users/uidA": {isVerified: false},
      [path]: {providerSessionId: "sess_1", lastEventId: "evt_1", lastEventAtMs: NOW},
    });
    const result = await applyIdentityProviderEvent(db, event(), "didit");
    assert.equal(result.applied, false);
    assert.equal(result.skipped, "duplicate");
    assert.notEqual(db.store.get("users/uidA").isVerified, true);
  });

  it("refuses to let a stale event walk a verified user backwards", async () => {
    const db = fakeDb({
      "users/uidA": {isVerified: true},
      [path]: {
        providerSessionId: "sess_1",
        status: "verified",
        lastEventId: "evt_2",
        lastEventAtMs: NOW,
      },
    });
    const result = await applyIdentityProviderEvent(
      db,
      event({eventId: "evt_1", status: "in_progress", occurredAtMs: NOW - 60_000}),
      "didit",
    );
    assert.equal(result.applied, false);
    assert.equal(result.skipped, "stale");
    assert.equal(db.store.get(path).status, "verified");
    assert.equal(db.store.get("users/uidA").isVerified, true);
  });

  it("refuses an event naming a session this user never started", async () => {
    const db = fakeDb({
      "users/uidA": {isVerified: false},
      [path]: {providerSessionId: "sess_mine", status: "pending"},
    });
    const result = await applyIdentityProviderEvent(
      db,
      event({providerSessionId: "sess_someone_else"}),
      "didit",
    );
    assert.equal(result.applied, false);
    assert.equal(result.skipped, "session_mismatch");
    assert.notEqual(db.store.get("users/uidA").isVerified, true);
  });

  it("does not resurrect a deleted account", async () => {
    const db = fakeDb({});
    const result = await applyIdentityProviderEvent(db, event(), "didit");
    assert.equal(result.applied, false);
    assert.equal(result.skipped, "no_such_user");
    assert.equal(db.store.has(path), false);
    assert.equal(db.store.has("users/uidA"), false);
  });
});

describe("decision summarizing and reasons", () => {
  it("reads only the four statuses MEVORA acts on", () => {
    const summary = summarizeDecision("sess_1", {
      status: "Declined",
      vendor_data: "uidA",
      id_verifications: [{status: "Approved", document_number: "X1234567", portrait_image: "https://cdn/x.jpg"}],
      liveness_checks: [{status: "Approved"}],
      face_matches: [{status: "Declined"}],
    });
    assert.deepEqual(summary, {
      sessionId: "sess_1",
      status: "Declined",
      vendorData: "uidA",
      idVerificationStatus: "Approved",
      livenessStatus: "Approved",
      faceMatchStatus: "Declined",
    });
    // Nothing identity-bearing survives the summary.
    const serialized = JSON.stringify(summary);
    assert.equal(serialized.includes("X1234567"), false);
    assert.equal(serialized.includes("cdn"), false);
  });

  it("maps a decline to the module that failed, not the provider's wording", () => {
    const base = {sessionId: "s", status: "Declined"};
    assert.equal(reasonForDecision("declined", {...base, faceMatchStatus: "Declined"}), "face_mismatch");
    assert.equal(reasonForDecision("declined", {...base, livenessStatus: "Declined"}), "liveness_failed");
    assert.equal(reasonForDecision("declined", {...base, idVerificationStatus: "Declined"}), "document_unreadable");
    assert.equal(reasonForDecision("in_review", base), "manual_review");
    assert.equal(reasonForDecision("verified", base), undefined);
  });
});
