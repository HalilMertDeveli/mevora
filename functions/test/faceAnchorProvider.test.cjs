const {describe, it, beforeEach, afterEach} = require("node:test");
const assert = require("node:assert/strict");
const {
  DiditFaceClient,
  DiditImageRejectedError,
  summarizeFaceMatch,
  summarizeLiveness,
} = require("../lib/identity/didit/diditFaceClient.js");
const {DiditApiError} = require("../lib/identity/didit/diditClient.js");
const {DiditFaceProvider} = require("../lib/faceAnchor/diditFaceProvider.js");
const {FaceProviderError} = require("../lib/faceAnchor/provider.js");
const {EmulatorFakeFaceProvider, FACE_ANCHOR_DEV_CONTROL_DOC} = require("../lib/faceAnchor/fakeProvider.js");
const {resolveFaceVerificationProvider} = require("../lib/faceAnchor/resolveProvider.js");
const {isFaceAnchorEnforced} = require("../lib/faceAnchor/faceAnchorConfig.js");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");

const API_KEY = "didit_test_api_key";
const SELFIE = Buffer.from("selfie-bytes");
const REFERENCE = Buffer.from("reference-bytes");

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

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
});

const client = (over = {}) => new DiditFaceClient({
  apiKey: API_KEY,
  baseUrl: "https://verification.didit.me",
  timeoutMs: 1000,
  ...over,
});
const provider = (thresholds = {liveness: 30, match: 50}) => new DiditFaceProvider(client(), thresholds);

/** A liveness body as Didit documents it, sensitive fields included. */
const livenessBody = (over = {}) => ({
  request_id: "req_11111111-2222-3333-4444-555555555555",
  liveness: {
    status: "Approved",
    method: "PASSIVE",
    score: 91.7,
    user_image: {entities: [{bbox: [1, 2, 3, 4], confidence: 0.99, age: 31.4, gender: "male"}], best_angle: 0},
    warnings: [],
    face_quality: 77.1,
    face_luminance: 50.2,
    ...over,
  },
  created_at: "2026-10-01T09:00:00Z",
});

const matchBody = (over = {}) => ({
  request_id: "req_aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  face_match: {
    status: "Approved",
    score: 83.25,
    user_image: {entities: [{bbox: [1, 2, 3, 4], age: 31.4, gender: "male"}]},
    ref_image: {entities: [{bbox: [5, 6, 7, 8], age: 30.9, gender: "male"}]},
    warnings: [],
    ...over,
  },
});

describe("Didit face client — what is sent", () => {
  it("posts multipart to the v3 standalone endpoints with the API key", async () => {
    const calls = mockFetch((url) => jsonResponse(200, url.includes("liveness") ? livenessBody() : matchBody()));
    await client().passiveLiveness({image: SELFIE, declineThreshold: 30});
    await client().faceMatch({userImage: SELFIE, referenceImage: REFERENCE, declineThreshold: 50});
    assert.deepEqual(calls.map((c) => c.url), [
      "https://verification.didit.me/v3/passive-liveness/",
      "https://verification.didit.me/v3/face-match/",
    ]);
    for (const call of calls) {
      assert.equal(call.init.method, "POST");
      assert.equal(call.init.headers["x-api-key"], API_KEY);
      assert.ok(call.init.body instanceof FormData);
      // The multipart boundary must come from fetch, not from us.
      assert.equal("Content-Type" in call.init.headers, false);
    }
  });

  it("always asks Didit not to keep the request", async () => {
    const calls = mockFetch((url) => jsonResponse(200, url.includes("liveness") ? livenessBody() : matchBody()));
    await client().passiveLiveness({image: SELFIE, declineThreshold: 30});
    await client().faceMatch({userImage: SELFIE, referenceImage: REFERENCE, declineThreshold: 50});
    for (const call of calls) {
      assert.equal(call.init.body.get("save_api_request"), "false");
    }
  });

  it("sends no member identifier and no metadata", async () => {
    const calls = mockFetch((url) => jsonResponse(200, url.includes("liveness") ? livenessBody() : matchBody()));
    await client().passiveLiveness({image: SELFIE, declineThreshold: 30});
    await client().faceMatch({userImage: SELFIE, referenceImage: REFERENCE, declineThreshold: 50});
    assert.deepEqual([...calls[0].init.body.keys()].sort(),
      ["face_liveness_score_decline_threshold", "save_api_request", "user_image"]);
    assert.deepEqual([...calls[1].init.body.keys()].sort(),
      ["face_match_score_decline_threshold", "ref_image", "save_api_request", "user_image"]);
  });

  it("names each image part with an extension Didit accepts, and passes the thresholds", async () => {
    const calls = mockFetch(() => jsonResponse(200, matchBody()));
    await client().faceMatch({userImage: SELFIE, referenceImage: REFERENCE, declineThreshold: 55});
    const body = calls[0].init.body;
    assert.equal(body.get("user_image").name, "selfie.jpg");
    assert.equal(body.get("ref_image").name, "reference.jpg");
    assert.equal(body.get("user_image").type, "image/jpeg");
    assert.equal(body.get("face_match_score_decline_threshold"), "55");
    assert.deepEqual(Buffer.from(await body.get("ref_image").arrayBuffer()), REFERENCE);
  });
});

describe("Didit face client — what is kept", () => {
  it("keeps the verdict word and risk codes, nothing else", () => {
    const summary = summarizeLiveness(livenessBody({
      status: "Declined",
      warnings: [{
        risk: "LOW_LIVENESS_SCORE",
        feature: "LIVENESS",
        log_type: "error",
        short_description: "Low liveness score",
        long_description: "The liveness score 12.3 is below the threshold.",
        additional_data: {score: 12.3},
      }],
    }));
    assert.deepEqual(summary, {status: "Declined", risks: ["LOW_LIVENESS_SCORE"]});
  });

  it("reduces a face match to the verdict, risk codes and a face count", () => {
    assert.deepEqual(summarizeFaceMatch(matchBody()), {status: "Approved", risks: [], referenceFaceCount: 1});
  });

  it("never returns a score, an age, a gender, a box or the request id", async () => {
    mockFetch((url) => jsonResponse(200, url.includes("liveness") ? livenessBody() : matchBody()));
    const kept = JSON.stringify([
      await client().passiveLiveness({image: SELFIE, declineThreshold: 30}),
      await client().faceMatch({userImage: SELFIE, referenceImage: REFERENCE, declineThreshold: 50}),
    ]);
    for (const leaked of ["score", "91.7", "83.25", "age", "gender", "bbox", "request_id", "req_", "quality"]) {
      assert.equal(kept.includes(leaked), false, `the summary must not carry ${leaked}`);
    }
  });

  it("drops anything in the warnings that is not a plain risk code", () => {
    const summary = summarizeLiveness(livenessBody({
      warnings: [{risk: "free text with a 0.93 score"}, {risk: 42}, null, {risk: "MULTIPLE_FACES_DETECTED"}],
    }));
    assert.deepEqual(summary.risks, ["MULTIPLE_FACES_DETECTED"]);
  });

  it("a body with no verdict word is an error, not an answer", () => {
    for (const body of [{}, null, {liveness: {}}, {liveness: {status: 7}}, {status: "Approved"}, "Approved"]) {
      assert.throws(() => summarizeLiveness(body), DiditApiError);
      assert.throws(() => summarizeFaceMatch(body), DiditApiError);
    }
  });
});

describe("Didit face provider — fail closed", () => {
  it("only the exact word Approved is live / a match", async () => {
    mockFetch((url) => jsonResponse(200, url.includes("liveness") ? livenessBody() : matchBody()));
    assert.equal(await provider().checkLiveness(SELFIE), "live");
    assert.equal(await provider().matchFaces(SELFIE, REFERENCE), "match");
  });

  it("Declined is a decline", async () => {
    mockFetch((url) => jsonResponse(200, url.includes("liveness")
      ? livenessBody({status: "Declined", warnings: [{risk: "LIVENESS_FACE_ATTACK"}]})
      : matchBody({status: "Declined", warnings: [{risk: "LOW_FACE_MATCH_SIMILARITY"}]})));
    assert.equal(await provider().checkLiveness(SELFIE), "not_live");
    assert.equal(await provider().matchFaces(SELFIE, REFERENCE), "no_match");
  });

  it("a verdict word it does not know is an error, never a pass", async () => {
    for (const status of ["approved", "APPROVED", "In Review", "Warning", "Passed", ""]) {
      mockFetch((url) => jsonResponse(200, url.includes("liveness") ? livenessBody({status}) : matchBody({status})));
      await assert.rejects(provider().checkLiveness(SELFIE), (e) => e instanceof FaceProviderError && !e.retryable);
      await assert.rejects(provider().matchFaces(SELFIE, REFERENCE), (e) => e instanceof FaceProviderError && !e.retryable);
    }
  });

  it("no face in the selfie is reported as such", async () => {
    mockFetch(() => jsonResponse(200, livenessBody({status: "Declined", warnings: [{risk: "NO_FACE_DETECTED"}]})));
    assert.equal(await provider().checkLiveness(SELFIE), "no_face");
  });

  it("a 400 means the image could not be used — a decision, not an outage", async () => {
    mockFetch(() => jsonResponse(400, {detail: "no face"}));
    assert.equal(await provider().checkLiveness(SELFIE), "no_face");
    assert.equal(await provider().matchFaces(SELFIE, REFERENCE), "reference_unusable");
    await assert.rejects(client().passiveLiveness({image: SELFIE, declineThreshold: 30}), DiditImageRejectedError);
  });

  it("a group photo cannot be an anchor even when Didit approves the match", async () => {
    mockFetch(() => jsonResponse(200, matchBody({ref_image: {entities: [{}, {}]}})));
    assert.equal(await provider().matchFaces(SELFIE, REFERENCE), "reference_unusable");
  });

  it("a reference with no face cannot be an anchor", async () => {
    mockFetch(() => jsonResponse(200, matchBody({status: "Declined", ref_image: {entities: []}, warnings: [{risk: "NO_REFERENCE_IMAGE"}]})));
    assert.equal(await provider().matchFaces(SELFIE, REFERENCE), "reference_unusable");
  });

  it("5xx and 429 are retryable outages", async () => {
    for (const status of [500, 502, 503, 429]) {
      mockFetch(() => jsonResponse(status, {}));
      await assert.rejects(provider().checkLiveness(SELFIE),
        (e) => e instanceof FaceProviderError && e.retryable && !e.unavailable);
    }
  });

  it("401 and 403 — bad key or no credits — are unavailable, not retryable", async () => {
    for (const status of [401, 403]) {
      mockFetch(() => jsonResponse(status, {error: "insufficient credits"}));
      await assert.rejects(provider().matchFaces(SELFIE, REFERENCE),
        (e) => e instanceof FaceProviderError && !e.retryable && e.unavailable);
    }
  });

  it("a network failure or timeout is a retryable outage that carries no detail", async () => {
    globalThis.fetch = async () => {
      throw new Error("connect ECONNREFUSED 10.1.2.3:443 secret-internal-detail");
    };
    await assert.rejects(provider().checkLiveness(SELFIE), (e) =>
      e instanceof FaceProviderError && e.retryable && !e.message.includes("ECONNREFUSED"));
  });

  it("aborts a request that outlives its timeout", async () => {
    globalThis.fetch = (url, init) => new Promise((resolve, reject) => {
      init.signal.addEventListener("abort", () => reject(new Error("aborted")));
    });
    const slow = new DiditFaceProvider(client({timeoutMs: 20}), {liveness: 30, match: 50});
    await assert.rejects(slow.checkLiveness(SELFIE), (e) => e instanceof FaceProviderError && e.retryable);
  });

  it("an unparseable 200 is an error", async () => {
    mockFetch(() => ({ok: true, status: 200, json: async () => {
      throw new Error("not json");
    }}));
    await assert.rejects(provider().checkLiveness(SELFIE), FaceProviderError);
  });
});

describe("provider selection — server environment only", () => {
  const KEYS = ["FUNCTIONS_EMULATOR", "DIDIT_API_KEY", "DIDIT_ENVIRONMENT", "DIDIT_BASE_URL", "FACE_ANCHOR_ENFORCEMENT"];
  let saved;
  beforeEach(() => {
    saved = Object.fromEntries(KEYS.map((k) => [k, process.env[k]]));
    for (const key of KEYS) delete process.env[key];
  });
  afterEach(() => {
    for (const key of KEYS) {
      if (saved[key] === undefined) delete process.env[key];
      else process.env[key] = saved[key];
    }
  });
  const db = createFakeFirestore();

  it("no provider at all when nothing is configured", () => {
    assert.equal(resolveFaceVerificationProvider(db), null);
  });

  it("a key without a declared live environment gets no provider", () => {
    // A sandbox key answers the standalone APIs with a canned approval; using
    // it would verify everybody.
    process.env.DIDIT_API_KEY = API_KEY;
    assert.equal(resolveFaceVerificationProvider(db), null);
    process.env.DIDIT_ENVIRONMENT = "sandbox";
    assert.equal(resolveFaceVerificationProvider(db), null);
    process.env.DIDIT_ENVIRONMENT = "LIVE";
    assert.equal(resolveFaceVerificationProvider(db), null);
  });

  it("Didit only when the deployment is declared live", () => {
    process.env.DIDIT_API_KEY = API_KEY;
    process.env.DIDIT_ENVIRONMENT = "live";
    assert.equal(resolveFaceVerificationProvider(db).id, "didit");
  });

  it("needs no workflow id or webhook secret", () => {
    process.env.DIDIT_API_KEY = API_KEY;
    process.env.DIDIT_ENVIRONMENT = "live";
    assert.equal(process.env.DIDIT_WORKFLOW_ID, undefined);
    assert.ok(resolveFaceVerificationProvider(db));
  });

  it("the emulator always gets the fake, never Didit", () => {
    process.env.FUNCTIONS_EMULATOR = "true";
    process.env.DIDIT_API_KEY = API_KEY;
    process.env.DIDIT_ENVIRONMENT = "live";
    assert.equal(resolveFaceVerificationProvider(db).id, "emulator-fake");
  });

  it("the fake refuses to exist outside the emulator", () => {
    assert.throws(() => new EmulatorFakeFaceProvider(db), /not available outside the emulator/);
    process.env.FUNCTIONS_EMULATOR = "1";
    assert.throws(() => new EmulatorFakeFaceProvider(db));
  });

  it("enforcement is off in a deployment until switched on, and on in the emulator", () => {
    assert.equal(isFaceAnchorEnforced(), false);
    process.env.FACE_ANCHOR_ENFORCEMENT = "on";
    assert.equal(isFaceAnchorEnforced(), true);
    process.env.FACE_ANCHOR_ENFORCEMENT = "yes";
    assert.equal(isFaceAnchorEnforced(), false);
    delete process.env.FACE_ANCHOR_ENFORCEMENT;
    process.env.FUNCTIONS_EMULATOR = "true";
    assert.equal(isFaceAnchorEnforced(), true);
    process.env.FACE_ANCHOR_ENFORCEMENT = "off";
    assert.equal(isFaceAnchorEnforced(), false);
  });
});

describe("emulator fake provider", () => {
  let saved;
  beforeEach(() => {
    saved = process.env.FUNCTIONS_EMULATOR;
    process.env.FUNCTIONS_EMULATOR = "true";
  });
  afterEach(() => {
    if (saved === undefined) delete process.env.FUNCTIONS_EMULATOR;
    else process.env.FUNCTIONS_EMULATOR = saved;
  });

  async function outcomeOf(control) {
    const db = createFakeFirestore(control ? {[FACE_ANCHOR_DEV_CONTROL_DOC]: control} : {});
    const fake = new EmulatorFakeFaceProvider(db);
    const result = {db};
    try {
      result.liveness = await fake.checkLiveness(SELFIE);
      result.match = await fake.matchFaces(SELFIE, REFERENCE);
    } catch (error) {
      result.error = error;
    }
    return result;
  }

  it("succeeds when no outcome is set", async () => {
    assert.deepEqual([(await outcomeOf()).liveness, (await outcomeOf()).match], ["live", "match"]);
  });

  it("produces each deterministic outcome", async () => {
    assert.equal((await outcomeOf({outcome: "liveness_failed"})).liveness, "not_live");
    const mismatch = await outcomeOf({outcome: "face_mismatch"});
    assert.deepEqual([mismatch.liveness, mismatch.match], ["live", "no_match"]);
    const error = (await outcomeOf({outcome: "provider_error"})).error;
    assert.ok(error instanceof FaceProviderError && error.retryable);
  });

  it("an unknown outcome is treated as success, not as a new behaviour", async () => {
    assert.equal((await outcomeOf({outcome: "verified-by-magic"})).match, "match");
  });

  it("a one-shot outcome is consumed", async () => {
    const {db, liveness} = await outcomeOf({outcome: "liveness_failed", once: true});
    assert.equal(liveness, "not_live");
    assert.equal(db.has(FACE_ANCHOR_DEV_CONTROL_DOC), false);
  });
});
