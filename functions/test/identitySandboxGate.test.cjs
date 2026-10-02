/**
 * A sandbox Didit application mocks its analysis: every document, liveness
 * check and face match is answered from a script, not from a person. A
 * deployment left on a sandbox key would therefore hand the verified badge to
 * anyone who walked through the hosted flow.
 *
 * So outside the Functions emulator a sandbox configuration may not verify
 * anyone, unless DIDIT_ALLOW_SANDBOX_VERIFICATION says — explicitly — that
 * this project is one where a mocked badge is acceptable.
 *
 * These drive the deployed wrappers (the callable and the HTTP webhook), not a
 * helper, so the refusal is observed where a client and Didit would meet it.
 */
const {describe, it, beforeEach, after} = require("node:test");
const assert = require("node:assert/strict");
const {createHmac} = require("node:crypto");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

process.env.FIREBASE_CONFIG = JSON.stringify({
  projectId: "demo-identity-gate",
  storageBucket: "demo-identity-gate.appspot.com",
});
process.env.GCLOUD_PROJECT = "demo-identity-gate";

// Both entry points bind getFirestore() at load, so the double goes in first.
const db = createFakeFirestore();
installFirebaseAdminStubs({db});

const {
  canDiditGrantVerification,
  canonicalizeDiditPayload,
} = require("../lib/identity/index.js");
const {createIdentityVerificationSession} = require("../lib/identity/createIdentityVerificationSession.js");
const {identityVerificationWebhook} = require("../lib/identity/identityVerificationWebhook.js");

const UID = "uidA";
const SESSION = "sess_1";
const WEBHOOK_SECRET = "whsec_test_shared_key";
const VERIFICATION = `users/${UID}/verification/identity`;

const KEYS = [
  "FUNCTIONS_EMULATOR",
  "DIDIT_API_KEY",
  "DIDIT_WEBHOOK_SECRET",
  "DIDIT_WORKFLOW_ID",
  "DIDIT_ENVIRONMENT",
  "DIDIT_ALLOW_SANDBOX_VERIFICATION",
  "DIDIT_BASE_URL",
  "DIDIT_CALLBACK_URL",
];
const saved = Object.fromEntries(KEYS.map((key) => [key, process.env[key]]));
const realFetch = globalThis.fetch;

/** A fully configured deployment; each test then declares its environment. */
function configure({environment, allowSandbox, emulator = false} = {}) {
  for (const key of KEYS) delete process.env[key];
  process.env.DIDIT_API_KEY = "didit_test_api_key";
  process.env.DIDIT_WEBHOOK_SECRET = WEBHOOK_SECRET;
  process.env.DIDIT_WORKFLOW_ID = "wf_test";
  if (environment !== undefined) process.env.DIDIT_ENVIRONMENT = environment;
  if (allowSandbox !== undefined) process.env.DIDIT_ALLOW_SANDBOX_VERIFICATION = allowSandbox;
  if (emulator) process.env.FUNCTIONS_EMULATOR = "true";
}

let providerCalls;
function mockDidit() {
  providerCalls = [];
  globalThis.fetch = async (url, init = {}) => {
    providerCalls.push({url: String(url), method: init.method ?? "GET"});
    const body = String(url).includes("/decision/")
      ? {session_id: SESSION, status: "Approved", vendor_data: UID}
      : {session_id: "sess_new", session_token: "tok_new", url: "https://verify.example/s/new", status: "Not Started"};
    return {ok: true, status: 200, json: async () => body, text: async () => JSON.stringify(body)};
  };
}

beforeEach(() => {
  mockDidit();
});

after(() => {
  globalThis.fetch = realFetch;
  for (const key of KEYS) {
    if (saved[key] === undefined) delete process.env[key];
    else process.env[key] = saved[key];
  }
});

const read = async (path) => (await db.doc(path).get()).data();

// ---------------------------------------------------------------------------
// The rule
// ---------------------------------------------------------------------------

describe("which configuration may grant the verified badge", () => {
  it("refuses a deployed sandbox configuration", () => {
    configure({environment: "sandbox"});
    assert.equal(canDiditGrantVerification(), false);
  });

  it("refuses a deployment that never declared its environment", () => {
    // DIDIT_ENVIRONMENT defaults to sandbox, so "forgot to set it" and "left
    // it on sandbox" are the same state and get the same answer.
    configure({});
    assert.equal(canDiditGrantVerification(), false);

    configure({environment: "production"});
    assert.equal(canDiditGrantVerification(), false, "only the exact string 'live' is live");
  });

  it("allows a live configuration, with or without the sandbox switch", () => {
    configure({environment: "live"});
    assert.equal(canDiditGrantVerification(), true);

    configure({environment: "live", allowSandbox: "true"});
    assert.equal(canDiditGrantVerification(), true);
  });

  it("allows a deployed sandbox only on the explicit opt-in", () => {
    configure({environment: "sandbox", allowSandbox: "true"});
    assert.equal(canDiditGrantVerification(), true);
  });

  it("reads nothing but the exact word as an opt-in", () => {
    for (const value of ["", "false", "1", "yes", "on", "TRUE", "True", "sandbox"]) {
      configure({environment: "sandbox", allowSandbox: value});
      assert.equal(canDiditGrantVerification(), false, `'${value}' must not opt in`);
    }
  });

  it("leaves the emulator exactly as it was", () => {
    configure({environment: "sandbox", emulator: true});
    assert.equal(canDiditGrantVerification(), true);

    configure({emulator: true});
    assert.equal(canDiditGrantVerification(), true);
  });
});

// ---------------------------------------------------------------------------
// Session creation
// ---------------------------------------------------------------------------

describe("createIdentityVerificationSession under each configuration", () => {
  beforeEach(() => {
    db.reset({[`users/${UID}`]: {uid: UID, isVerified: false}});
  });

  it("refuses a deployed sandbox configuration, and creates nothing", async () => {
    configure({environment: "sandbox"});

    await assert.rejects(
      () => callAs(createIdentityVerificationSession, UID),
      (error) => {
        assert.equal(error.code, "failed-precondition");
        // The same answer the app already handles for an unconfigured backend.
        assert.equal(error.message, "verification-not-configured");
        return true;
      },
    );

    assert.deepEqual(providerCalls, [], "no provider session may be created");
    assert.equal(await read(VERIFICATION), undefined, "no attempt may be reserved");
  });

  it("refuses when the environment was never declared", async () => {
    configure({});
    await assert.rejects(
      () => callAs(createIdentityVerificationSession, UID),
      (error) => error.code === "failed-precondition" && error.message === "verification-not-configured",
    );
    assert.deepEqual(providerCalls, []);
  });

  it("does not hand back an in-flight sandbox session either", async () => {
    // Resuming is session creation by another name: it would put the member
    // back into a flow whose verdict cannot count.
    configure({environment: "sandbox"});
    db.reset({
      [`users/${UID}`]: {uid: UID, isVerified: false},
      [VERIFICATION]: {provider: "didit", status: "pending", providerSessionId: SESSION, attemptCount: 1},
    });

    await assert.rejects(
      () => callAs(createIdentityVerificationSession, UID),
      (error) => error.message === "verification-not-configured",
    );
    assert.deepEqual(providerCalls, []);
  });

  for (const [label, options] of [
    ["a deployed sandbox with the explicit opt-in", {environment: "sandbox", allowSandbox: "true"}],
    ["a live configuration", {environment: "live"}],
    ["the emulator on sandbox", {environment: "sandbox", emulator: true}],
  ]) {
    it(`still creates a session for ${label}`, async () => {
      configure(options);

      const result = await callAs(createIdentityVerificationSession, UID);

      assert.equal(result.providerSessionId, "sess_new");
      assert.equal(result.resumed, false);
      assert.equal(providerCalls.length, 1);
      assert.match(providerCalls[0].url, /\/v3\/session\/$/);
      const doc = await read(VERIFICATION);
      assert.equal(doc.status, "pending");
      assert.equal(doc.providerSessionId, "sess_new");
    });
  }
});

// ---------------------------------------------------------------------------
// The webhook
// ---------------------------------------------------------------------------

/** Drives the deployed onRequest wrapper with a signed Didit delivery. */
function deliver(payload) {
  const rawBody = JSON.stringify(payload);
  const seconds = Math.floor(Date.now() / 1000);
  const headers = {
    "content-type": "application/json",
    "x-signature-v2": createHmac("sha256", WEBHOOK_SECRET)
      .update(canonicalizeDiditPayload(payload), "utf8")
      .digest("hex"),
    "x-timestamp": String(seconds),
  };
  return new Promise((resolve) => {
    const req = {
      method: "POST",
      headers,
      body: payload,
      rawBody: Buffer.from(rawBody),
      get(name) {
        return this.headers[String(name).toLowerCase()];
      },
      header(name) {
        return this.get(name);
      },
      on() {},
    };
    const res = {
      statusCode: 200,
      status(code) {
        this.statusCode = code;
        return this;
      },
      setHeader() {
        return this;
      },
      getHeader() {},
      set() {
        return this;
      },
      removeHeader() {},
      on() {},
      json(body) {
        resolve({status: this.statusCode, body});
      },
      send(body) {
        resolve({status: this.statusCode, body});
      },
      end() {
        resolve({status: this.statusCode, body: null});
      },
    };
    identityVerificationWebhook(req, res);
  });
}

const delivery = (status, over = {}) => ({
  event_id: `evt_${status}`,
  webhook_type: "status.updated",
  session_id: SESSION,
  vendor_data: UID,
  status,
  timestamp: Math.floor(Date.now() / 1000),
  environment: "sandbox",
  ...over,
});

function seedInFlight({verified = false} = {}) {
  db.reset({
    [`users/${UID}`]: {uid: UID, isVerified: verified},
    [`profiles/${UID}`]: {uid: UID, isVerified: verified},
    [VERIFICATION]: {
      provider: "didit",
      status: verified ? "verified" : "pending",
      providerSessionId: SESSION,
      attemptCount: 1,
    },
  });
}

describe("identityVerificationWebhook under each configuration", () => {
  it("does not verify anyone on a deployed sandbox approval", async () => {
    configure({environment: "sandbox"});
    seedInFlight();

    const result = await deliver(delivery("Approved"));

    // Acknowledged: a redelivery could never succeed, so Didit must not be
    // asked to keep trying.
    assert.equal(result.status, 200);
    assert.equal(result.body.ok, true);
    assert.equal(result.body.applied, false);
    assert.equal(result.body.skipped, "sandbox_verification_disabled");

    assert.equal((await read(`users/${UID}`)).isVerified, false);
    assert.equal((await read(`profiles/${UID}`)).isVerified, false);
    const doc = await read(VERIFICATION);
    assert.equal(doc.status, "pending", "the record must not say verified");
    assert.equal(doc.verifiedAt, undefined);
    assert.equal(doc.lastEventId, undefined, "the approval must leave no trace on the record");
    // It never even asks: no answer from a sandbox application could count.
    assert.deepEqual(providerCalls, []);
  });

  it("does not verify anyone when the environment was never declared", async () => {
    configure({});
    seedInFlight();

    const result = await deliver(delivery("Approved"));

    assert.equal(result.status, 200);
    assert.equal(result.body.applied, false);
    assert.equal((await read(`users/${UID}`)).isVerified, false);
    assert.equal((await read(VERIFICATION)).status, "pending");
  });

  it("still applies an outcome that only takes the badge away", async () => {
    // The gate withholds the badge; it is not a reason to keep one. A decline
    // moves a member away from verified, which is the safe direction in any
    // configuration.
    configure({environment: "sandbox"});
    seedInFlight({verified: true});

    const result = await deliver(delivery("Declined"));

    assert.equal(result.status, 200);
    assert.equal(result.body.applied, true);
    assert.equal((await read(`users/${UID}`)).isVerified, false);
    assert.equal((await read(`profiles/${UID}`)).isVerified, false);
    assert.equal((await read(VERIFICATION)).status, "declined");
  });

  it("still rejects a forged delivery before it says anything about configuration", async () => {
    configure({environment: "sandbox"});
    seedInFlight();
    process.env.DIDIT_WEBHOOK_SECRET = "a_different_secret";

    const result = await deliver(delivery("Approved"));

    assert.equal(result.status, 401);
    assert.equal((await read(`users/${UID}`)).isVerified, false);
  });

  for (const [label, options] of [
    ["a deployed sandbox with the explicit opt-in", {environment: "sandbox", allowSandbox: "true"}],
    ["a live configuration", {environment: "live"}],
    ["the emulator on sandbox", {environment: "sandbox", emulator: true}],
  ]) {
    it(`still verifies on a confirmed approval for ${label}`, async () => {
      configure(options);
      seedInFlight();

      const result = await deliver(delivery("Approved"));

      assert.equal(result.status, 200);
      assert.equal(result.body.applied, true);
      assert.equal((await read(`users/${UID}`)).isVerified, true);
      assert.equal((await read(`profiles/${UID}`)).isVerified, true);
      assert.equal((await read(VERIFICATION)).status, "verified");
      // The approval is still confirmed server to server before it counts.
      assert.equal(providerCalls.length, 1);
      assert.match(providerCalls[0].url, /\/v3\/session\/sess_1\/decision\/$/);
    });
  }
});
