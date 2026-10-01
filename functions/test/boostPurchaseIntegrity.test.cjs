/**
 * A Play purchase token buys exactly one Boost grant, for exactly one account.
 *
 * The ledger used to be keyed by the transaction id the client sent, so the
 * same token with a different id — or from a different account — was granted
 * again. These suites pin the token itself as the identity.
 */
const {after, before, beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const {Timestamp} = require("firebase-admin/firestore");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

const fake = createFakeFirestore();
let autoId = 0;
const db = {
  ...fake,
  // The double has neither auto ids nor add(); the callable and sendUserPush need both.
  collection: (path) => {
    const ref = fake.collection(path);
    return {
      ...ref,
      doc: (id) => ref.doc(id ?? `auto${++autoId}`),
      add: async (data) => {
        const doc = ref.doc(`auto${++autoId}`);
        await doc.set(data);
        return doc;
      },
    };
  },
};
installFirebaseAdminStubs({db});

const {verifyBoostPurchase, grantBoostPurchase} = require("../lib/boost/verifyBoostPurchase.js");
const {ApplePurchaseVerifier} = require("../lib/boost/applePurchaseVerifier.js");
const {GooglePurchaseVerifier} = require("../lib/boost/googlePurchaseVerifier.js");
const {PurchaseVerificationService} = require("../lib/boost/purchaseVerificationService.js");

const WEEK = "mevora_boost_7_days";
const FIVE_PACK = "com.mevora.app.boost.5";
const DAY_MS = 24 * 60 * 60 * 1000;
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

const purchasePaths = () => fake.paths().filter((path) => path.startsWith("purchases/"));
const boostPaths = (uid) => fake.paths().filter((path) => path.startsWith(`users/${uid}/boosts/`));
const balance = (uid) => fake.read(`users/${uid}/boostWallet/current`)?.balance ?? 0;
const daysGranted = (uid) => {
  const [path] = boostPaths(uid);
  return Math.round((fake.read(path).expiresAt.toMillis() - Date.now()) / DAY_MS);
};
const request = (overrides = {}) => ({
  platform: "android",
  productId: WEEK,
  transactionId: "GPA.3300-0000-0000-00001",
  purchaseToken: "play-token-1",
  ...overrides,
});
const rejectedWith = (code) => (error) => {
  assert.equal(error.code, code);
  return true;
};

beforeEach(() => {
  fake.reset({});
  autoId = 0;
});

describe("boost purchase ledger — one grant per Play purchase token", () => {
  const saved = {};
  before(() => {
    saved.emulator = process.env.FUNCTIONS_EMULATOR;
    saved.account = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON;
    // The emulator verifier accepts any token, which isolates the ledger rules.
    process.env.FUNCTIONS_EMULATOR = "true";
    delete process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON;
  });
  after(() => {
    for (const [key, name] of [["emulator", "FUNCTIONS_EMULATOR"], ["account", "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"]]) {
      if (saved[key] === undefined) delete process.env[name];
      else process.env[name] = saved[key];
    }
  });

  it("keys the ledger by the token hash, never by the client's transaction id", async () => {
    const result = await callAs(verifyBoostPurchase, "u1", request());

    assert.equal(result.ok, true);
    assert.equal(result.alreadyProcessed, false);
    assert.deepEqual(purchasePaths(), [`purchases/android_${sha256("play-token-1")}`]);
    assert.equal(result.purchase.purchaseId, `android_${sha256("play-token-1")}`);
    const ledger = fake.read(purchasePaths()[0]);
    assert.equal(ledger.userId, "u1");
    assert.equal(ledger.purchaseTokenHashOrReference, sha256("play-token-1"));
    assert.ok(!JSON.stringify(ledger).includes("play-token-1"), "the raw token is never stored");
  });

  it("the same token with a different transaction id is granted once", async () => {
    await callAs(verifyBoostPurchase, "u1", request());
    const replay = await callAs(verifyBoostPurchase, "u1", request({transactionId: "GPA.forged-2"}));

    assert.equal(replay.ok, true);
    assert.equal(replay.alreadyProcessed, true);
    assert.equal(purchasePaths().length, 1);
    assert.equal(boostPaths("u1").length, 1);
    assert.equal(daysGranted("u1"), 7, "a replay must not stack another week");
  });

  it("the same token replayed for a count pack credits the wallet once", async () => {
    const pack = {productId: FIVE_PACK, purchaseToken: "play-token-pack"};
    await callAs(verifyBoostPurchase, "u1", request(pack));
    await callAs(verifyBoostPurchase, "u1", request({...pack, transactionId: "GPA.forged-2"}));
    await callAs(verifyBoostPurchase, "u1", request({...pack, transactionId: "GPA.forged-3"}));

    assert.equal(balance("u1"), 5);
  });

  it("the same token from a second account is rejected and grants nothing", async () => {
    await callAs(verifyBoostPurchase, "u1", request());

    await assert.rejects(callAs(verifyBoostPurchase, "u2", request()), rejectedWith("already-exists"));
    await assert.rejects(
      callAs(verifyBoostPurchase, "u2", request({transactionId: "GPA.forged-2"})),
      rejectedWith("already-exists"),
    );

    assert.equal(purchasePaths().length, 1);
    assert.equal(fake.read(purchasePaths()[0]).userId, "u1");
    assert.deepEqual(boostPaths("u2"), []);
    assert.equal(balance("u2"), 0);
  });

  it("a retry by the same account returns the same purchase without a second grant", async () => {
    const first = await callAs(verifyBoostPurchase, "u1", request());
    const retry = await callAs(verifyBoostPurchase, "u1", request());

    assert.equal(retry.ok, true);
    assert.equal(retry.alreadyProcessed, true);
    assert.equal(retry.purchase.purchaseId, first.purchase.purchaseId);
    assert.equal(retry.boost.boostId, first.boost.boostId);
    assert.equal(retry.boost.expiresAt, first.boost.expiresAt);
    assert.equal(daysGranted("u1"), 7);
  });

  it("two simultaneous submissions of one token grant once", async () => {
    const pack = {productId: FIVE_PACK, purchaseToken: "play-token-race"};
    const results = await Promise.all([
      callAs(verifyBoostPurchase, "u1", request(pack)),
      callAs(verifyBoostPurchase, "u1", request({...pack, transactionId: "GPA.forged-2"})),
    ]);

    assert.deepEqual(results.map((result) => result.alreadyProcessed).sort(), [false, true]);
    assert.equal(balance("u1"), 5);
    assert.equal(purchasePaths().length, 1);
  });

  it("two accounts submitting one token at the same moment: one is granted, one is rejected", async () => {
    const pack = {productId: FIVE_PACK, purchaseToken: "play-token-race"};
    const results = await Promise.allSettled([
      callAs(verifyBoostPurchase, "u1", request(pack)),
      callAs(verifyBoostPurchase, "u2", request({...pack, transactionId: "GPA.forged-2"})),
    ]);

    assert.deepEqual(results.map((result) => result.status).sort(), ["fulfilled", "rejected"]);
    assert.equal(results.find((result) => result.status === "rejected").reason.code, "already-exists");
    assert.equal(balance("u1") + balance("u2"), 5);
    assert.equal(purchasePaths().length, 1);
  });

  describe("ledger entries written before the token became the key", () => {
    // Shape of a document the previous version wrote: id from the client's
    // transaction id, with the token hash alongside.
    const legacy = (userId) => ({
      "purchases/android_GPA.3300-0000-0000-00001": {
        purchaseId: "android_GPA.3300-0000-0000-00001",
        userId,
        productId: WEEK,
        boostCount: 0,
        durationDays: 7,
        durationMs: 7 * DAY_MS,
        platform: "android",
        transactionId: "GPA.3300-0000-0000-00001",
        purchaseTokenHashOrReference: sha256("play-token-1"),
        status: "verified",
        purchasedAt: Timestamp.fromMillis(Date.now() - DAY_MS),
        verifiedAt: Timestamp.fromMillis(Date.now() - DAY_MS),
        createdAt: Timestamp.fromMillis(Date.now() - DAY_MS),
      },
    });

    it("block a re-grant to the same account under a new transaction id", async () => {
      fake.reset(legacy("u1"));

      const replay = await callAs(verifyBoostPurchase, "u1", request({transactionId: "GPA.forged-2"}));

      assert.equal(replay.alreadyProcessed, true);
      assert.equal(replay.purchase.purchaseId, "android_GPA.3300-0000-0000-00001");
      assert.equal(purchasePaths().length, 1);
      assert.deepEqual(boostPaths("u1"), []);
    });

    it("block a grant to another account", async () => {
      fake.reset(legacy("u1"));

      await assert.rejects(
        callAs(verifyBoostPurchase, "u2", request({transactionId: "GPA.forged-2"})),
        rejectedWith("already-exists"),
      );

      assert.equal(purchasePaths().length, 1);
      assert.deepEqual(boostPaths("u2"), []);
    });

    it("prefer the caller's own entry when a token was already granted twice", async () => {
      fake.reset({
        ...legacy("u0"),
        "purchases/android_GPA.forged-9": {
          ...legacy("u1")["purchases/android_GPA.3300-0000-0000-00001"],
          purchaseId: "android_GPA.forged-9",
        },
      });

      const replay = await callAs(verifyBoostPurchase, "u1", request({transactionId: "GPA.forged-3"}));

      assert.equal(replay.alreadyProcessed, true);
      assert.equal(replay.purchase.purchaseId, "android_GPA.forged-9");
      assert.equal(purchasePaths().length, 2);
    });
  });
});

describe("boost purchase — Google Play verification and consumption", () => {
  /** The two Play Developer API endpoints the verifier calls, in memory. */
  function fakePlay() {
    const response = (status, body) => ({ok: status >= 200 && status < 300, status, json: async () => body});
    const play = {
      purchases: new Map(),
      calls: [],
      failConsume: null,
      onConsume: null,
      add(token, fields = {}) {
        play.purchases.set(token, {
          productId: WEEK,
          purchaseState: 0,
          consumptionState: 0,
          orderId: "GPA.3300-1111-2222-33333",
          purchaseTimeMillis: "1790000000000",
          ...fields,
        });
      },
      countOf: (kind) => play.calls.filter((call) => call.kind === kind).length,
      fetch: async (url, init = {}) => {
        const match = /\/purchases\/products\/([^/]+)\/tokens\/([^/:]+)(:consume)?$/.exec(String(url));
        const productId = decodeURIComponent(match[1]);
        const token = decodeURIComponent(match[2]);
        const kind = match[3] ? "consume" : "get";
        play.calls.push({kind, token, method: init.method ?? "GET", authorization: init.headers?.Authorization});
        const purchase = play.purchases.get(token);
        if (!purchase || purchase.productId !== productId) {
          return response(404, {});
        }
        if (kind === "get") {
          const {productId: _omit, ...body} = purchase;
          return response(200, body);
        }
        if (play.failConsume === "throw") {
          throw new Error("socket hang up");
        }
        if (play.failConsume) {
          return response(503, {});
        }
        play.onConsume?.(token);
        purchase.consumptionState = 1;
        return response(200, {});
      },
    };
    return play;
  }

  let play;
  let verification;
  const grant = (uid, overrides = {}) =>
    grantBoostPurchase({db, uid, payload: request(overrides), verification});

  const saved = {};
  before(() => {
    saved.emulator = process.env.FUNCTIONS_EMULATOR;
    delete process.env.FUNCTIONS_EMULATOR;
  });
  after(() => {
    if (saved.emulator !== undefined) process.env.FUNCTIONS_EMULATOR = saved.emulator;
  });
  beforeEach(() => {
    play = fakePlay();
    verification = new PurchaseVerificationService(
      new ApplePurchaseVerifier(),
      new GooglePurchaseVerifier({accessToken: async () => "play-access", fetch: play.fetch}),
    );
  });

  it("grants a purchase Google confirms, recorded under Google's order id", async () => {
    play.add("play-token-1");

    const result = await grant("u1", {transactionId: "whatever-the-client-says"});

    assert.equal(result.ok, true);
    assert.equal(result.alreadyProcessed, false);
    assert.equal(result.purchase.transactionId, "GPA.3300-1111-2222-33333");
    const ledger = fake.read(`purchases/android_${sha256("play-token-1")}`);
    assert.equal(ledger.transactionId, "GPA.3300-1111-2222-33333");
    assert.equal(ledger.userId, "u1");
    // The double stores `undefined`; Firestore rejects the whole write for it.
    for (const [field, value] of Object.entries(ledger)) {
      assert.notEqual(value, undefined, `${field} must not be undefined`);
    }
    assert.equal(daysGranted("u1"), 7);
    assert.equal(play.calls[0].authorization, "Bearer play-access");
  });

  it("consumes the purchase only after the grant is committed", async () => {
    play.add("play-token-1");
    const atConsume = {};
    play.onConsume = () => {
      atConsume.ledger = fake.has(`purchases/android_${sha256("play-token-1")}`);
      atConsume.boosts = boostPaths("u1").length;
    };

    await grant("u1");

    assert.deepEqual(atConsume, {ledger: true, boosts: 1});
    assert.deepEqual(play.calls.map((call) => `${call.method} ${call.kind}`), ["GET get", "POST consume"]);
    assert.equal(play.purchases.get("play-token-1").consumptionState, 1);
    assert.ok(fake.read(`purchases/android_${sha256("play-token-1")}`).consumedAt, "consumption is recorded");
  });

  it("rejects a token Google reports as already consumed when the ledger has no entry", async () => {
    play.add("play-token-1", {consumptionState: 1});

    await assert.rejects(grant("u1"), rejectedWith("invalid-argument"));

    assert.deepEqual(purchasePaths(), []);
    assert.deepEqual(boostPaths("u1"), []);
    assert.equal(play.countOf("consume"), 0);
  });

  it("rejects a purchase that is not in the purchased state", async () => {
    play.add("play-token-1", {purchaseState: 2});

    await assert.rejects(grant("u1"), rejectedWith("invalid-argument"));

    assert.deepEqual(purchasePaths(), []);
    assert.equal(play.countOf("consume"), 0);
  });

  it("rejects a token Google does not know and writes nothing", async () => {
    await assert.rejects(grant("u1", {purchaseToken: "made-up"}), rejectedWith("invalid-argument"));

    assert.deepEqual(purchasePaths(), []);
    assert.deepEqual(boostPaths("u1"), []);
  });

  for (const failure of ["status", "throw"]) {
    it(`a failed consume (${failure}) keeps the grant, and the retry consumes without granting again`, async () => {
      play.add("play-token-1");
      play.failConsume = failure;

      const first = await grant("u1");

      assert.equal(first.ok, true);
      assert.equal(first.alreadyProcessed, false);
      assert.equal(daysGranted("u1"), 7);
      assert.equal(play.purchases.get("play-token-1").consumptionState, 0);
      assert.equal(fake.read(`purchases/${first.purchase.purchaseId}`).consumedAt, undefined);

      play.failConsume = null;
      // Whatever the retry claims, it is answered — and consumed — from the ledger.
      const retry = await grant("u1", {transactionId: "GPA.forged-2", productId: "mevora_boost_1_month"});

      assert.equal(retry.alreadyProcessed, true);
      assert.equal(retry.purchase.purchaseId, first.purchase.purchaseId);
      assert.equal(daysGranted("u1"), 7, "the retry must not stack another week");
      assert.equal(purchasePaths().length, 1);
      assert.equal(boostPaths("u1").length, 1);
      assert.equal(play.purchases.get("play-token-1").consumptionState, 1, "the retry finishes the consume");
      assert.equal(play.countOf("get"), 1, "a recorded token is not verified with Google again");

      const consumes = play.countOf("consume");
      const again = await grant("u1");
      assert.equal(again.alreadyProcessed, true);
      assert.equal(play.countOf("consume"), consumes, "a consumed purchase is not consumed again");
      assert.equal(daysGranted("u1"), 7);
    });
  }

  it("a consumed, recorded token stays rejected for every other account", async () => {
    play.add("play-token-1");
    await grant("u1");

    await assert.rejects(grant("u2", {transactionId: "GPA.forged-2"}), rejectedWith("already-exists"));

    assert.deepEqual(boostPaths("u2"), []);
    assert.equal(play.countOf("get"), 1);
  });

  it("an unavailable Play API grants nothing and stays retryable", async () => {
    play.add("play-token-1");
    const failing = new PurchaseVerificationService(
      new ApplePurchaseVerifier(),
      new GooglePurchaseVerifier({
        accessToken: async () => "play-access",
        fetch: async () => ({ok: false, status: 503, json: async () => ({})}),
      }),
    );

    await assert.rejects(
      grantBoostPurchase({db, uid: "u1", payload: request(), verification: failing}),
      rejectedWith("unavailable"),
    );
    assert.deepEqual(purchasePaths(), []);

    const result = await grant("u1");
    assert.equal(result.alreadyProcessed, false);
    assert.equal(daysGranted("u1"), 7);
  });
});
