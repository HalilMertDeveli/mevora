/**
 * B-05 — callable App Check configuration regression.
 *
 * These assertions exercise the deployed callable wrapper, not a helper. The
 * enforceAppCheck option is captured in the onCall closure and is absent from
 * the exported __endpoint manifest, so configuration cannot be proven by
 * inspecting metadata — it has to be observed.
 *
 * The discriminator is established by a control pair below:
 *
 *   enforceAppCheck: true   + no App Check token -> rejected BEFORE the
 *                                                   handler runs, with
 *                                                   firebase-functions' own
 *                                                   "Unauthenticated" message
 *   enforceAppCheck: false  + no App Check token -> handler RUNS
 *
 * So "the handler did not run" is the signature of enforcement, and the real
 * callables are compared against the control's observed message rather than a
 * hardcoded string.
 */
const {describe, it, before} = require("node:test");
const assert = require("node:assert/strict");

process.env.FIREBASE_CONFIG = JSON.stringify({
  projectId: "demo-appcheck",
  storageBucket: "demo-appcheck.appspot.com",
});
process.env.GCLOUD_PROJECT = "demo-appcheck";

/** Minimal express req/res pair driving the callable protocol. */
function invokeCallable(fn, body = {data: {}}, headers = {}) {
  return new Promise((resolve) => {
    const req = {
      method: "POST",
      headers: Object.assign({"content-type": "application/json"}, headers),
      body,
      rawBody: Buffer.from(JSON.stringify(body)),
      get(h) {
        return this.headers[String(h).toLowerCase()];
      },
      header(h) {
        return this.get(h);
      },
      on() {},
    };
    const res = {
      statusCode: 200,
      _body: null,
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
      json(b) {
        this._body = b;
        resolve({status: this.statusCode, body: b});
      },
      send(b) {
        this._body = b;
        resolve({status: this.statusCode, body: b});
      },
      end() {
        resolve({status: this.statusCode, body: this._body});
      },
    };
    fn(req, res);
  });
}

const errorMessage = (result) => result.body?.error?.message ?? null;

/** Re-require social.js with FUNCTIONS_EMULATOR set or cleared. */
function loadSocial({emulator}) {
  if (emulator) {
    process.env.FUNCTIONS_EMULATOR = "true";
  } else {
    delete process.env.FUNCTIONS_EMULATOR;
  }
  const resolved = require.resolve("../lib/social.js");
  delete require.cache[resolved];
  return require("../lib/social.js");
}

let APP_CHECK_REJECTION;

describe("B-05 control — how App Check enforcement is observable", () => {
  before(async () => {
    delete process.env.FUNCTIONS_EMULATOR;
    const {onCall} = require("firebase-functions/v2/https");
    let enforcedRan = false;
    let openRan = false;
    const enforced = onCall({region: "europe-west1", enforceAppCheck: true}, async () => {
      enforcedRan = true;
      return {ok: true};
    });
    const open = onCall({region: "europe-west1", enforceAppCheck: false}, async () => {
      openRan = true;
      return {ok: true};
    });

    const enforcedResult = await invokeCallable(enforced);
    const openResult = await invokeCallable(open);

    // Enforcement rejects before the handler body executes.
    assert.equal(enforcedRan, false, "enforced handler must not run without App Check");
    assert.equal(enforcedResult.status, 401);
    // Without enforcement the handler runs even with no App Check token.
    assert.equal(openRan, true, "unenforced handler should run");
    assert.equal(openResult.status, 200);

    APP_CHECK_REJECTION = errorMessage(enforcedResult);
    assert.ok(APP_CHECK_REJECTION, "control must yield an App Check rejection message");
  });

  it("establishes a rejection signature distinct from a handler-level auth error", () => {
    // requireUid() throws HttpsError("unauthenticated", "unauthenticated"); the
    // App Check gate produces a different message, so the two are separable.
    assert.notEqual(APP_CHECK_REJECTION, "unauthenticated");
  });
});

describe("B-05 — LiveKit callables enforce App Check in production", () => {
  for (const name of ["createVideoCall", "respondToVideoCall"]) {
    it(`${name} is rejected at the App Check gate, before its handler runs`, async () => {
      const social = loadSocial({emulator: false});
      const result = await invokeCallable(social[name], {data: {}});
      assert.equal(result.status, 401);
      assert.equal(
        errorMessage(result),
        APP_CHECK_REJECTION,
        `${name} did not reject at the App Check gate — its options are missing enforceAppCheck`,
      );
    });

    it(`${name} still declares the LiveKit secrets`, () => {
      const social = loadSocial({emulator: false});
      const keys = (social[name].__endpoint.secretEnvironmentVariables ?? []).map((v) => v.key);
      assert.deepEqual(
        keys.sort(),
        ["LIVEKIT_API_KEY", "LIVEKIT_API_SECRET", "LIVEKIT_URL"],
        "spreading the shared config must not drop the secret declaration",
      );
    });

    it(`${name} keeps emulator behaviour — App Check is not enforced locally`, async () => {
      const social = loadSocial({emulator: true});
      const result = await invokeCallable(social[name], {data: {}});
      // The handler runs and its own auth guard rejects, so the message is the
      // handler's, not the App Check gate's.
      assert.notEqual(
        errorMessage(result),
        APP_CHECK_REJECTION,
        `${name} must not enforce production App Check under FUNCTIONS_EMULATOR`,
      );
      assert.equal(errorMessage(result), "unauthenticated");
    });
  }

  it("the sibling call callables were already enforcing and still are", async () => {
    const social = loadSocial({emulator: false});
    for (const name of ["endVideoCall", "expireVideoCall", "recordSwipe", "blockUser", "reportUser", "unmatchUser"]) {
      const result = await invokeCallable(social[name], {data: {}});
      assert.equal(
        errorMessage(result),
        APP_CHECK_REJECTION,
        `${name} regressed: no longer rejecting at the App Check gate`,
      );
    }
  });
});

describe("B-05 — no callable reintroduces the inline-options defect", () => {
  // The defect was declaring inline options because the shared config lacked
  // `secrets`. Guard the shape rather than the symptom.
  const {readFileSync} = require("node:fs");
  const {resolve} = require("node:path");
  const source = readFileSync(resolve(__dirname, "../src/social.ts"), "utf8");

  it("social.ts declares no onCall with bare inline options", () => {
    const inline = source.match(/onCall\(\s*\{[^}]*region:/g) ?? [];
    assert.deepEqual(
      inline,
      [],
      "a callable is declaring inline options again; spread socialCallable/livekitCallable instead",
    );
  });

  it("the LiveKit config is derived from the shared social config", () => {
    assert.match(source, /const livekitCallable = \{\s*\.\.\.socialCallable,/);
    assert.match(source, /export const createVideoCall = onCall\(\s*livekitCallable,/);
    assert.match(source, /export const respondToVideoCall = onCall\(\s*livekitCallable,/);
  });
});
