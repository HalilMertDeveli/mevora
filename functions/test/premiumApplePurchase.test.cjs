const {describe, it, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {
  verifyIosPremiumPurchase,
} = require("../lib/subscription/verifyPremiumPurchase.js");
const {
  PurchaseOwnershipConflict,
} = require("../lib/subscription/premiumPurchaseStore.js");
const {
  selectSubscriptionState,
  decodeJwsPayload,
} = require("../lib/subscription/appleSubscriptionVerifier.js");

const BUNDLE = "com.mevora.app";
const now = new Date("2026-09-27T12:00:00Z");
const EXPIRES = Date.parse("2026-10-27T12:00:00Z");

const saved = {};
before(() => {
  saved.bundle = process.env.PREMIUM_IOS_BUNDLE_ID;
  saved.ids = process.env.PREMIUM_IOS_PRODUCT_IDS;
  process.env.PREMIUM_IOS_BUNDLE_ID = BUNDLE;
  process.env.PREMIUM_IOS_PRODUCT_IDS = "mevora_premium_monthly,mevora_premium_yearly";
});
after(() => {
  process.env.PREMIUM_IOS_BUNDLE_ID = saved.bundle;
  process.env.PREMIUM_IOS_PRODUCT_IDS = saved.ids;
});

function memoryStore(seed = null) {
  const box = {state: seed, writes: 0, tokens: []};
  return {
    box,
    makeStore(args) {
      box.tokens.push(args.purchaseToken);
      return {
        async transact(userId, mutate) {
          const next = mutate(box.state);
          if (next) {
            box.state = next;
            box.writes += 1;
          }
          return box.state ?? {userId};
        },
      };
    },
  };
}

const conflictingStore = () => ({
  async transact() {
    throw new PurchaseOwnershipConflict("someone-else");
  },
});

const api = (result) => ({
  async fetchSubscription() {
    return result;
  },
});

function appleState(overrides = {}) {
  const {transaction = {}, renewal = {}, ...rest} = overrides;
  return {
    status: 1,
    expiresDate: EXPIRES,
    transaction: {
      bundleId: BUNDLE,
      productId: "mevora_premium_monthly",
      originalTransactionId: "1000000000000001",
      transactionId: "1000000000000009",
      environment: "Production",
      ...transaction,
    },
    renewal: {autoRenewStatus: 1, ...renewal},
    ...rest,
  };
}

function jws(payload) {
  const body = Buffer.from(JSON.stringify(payload), "utf8").toString("base64url");
  return `header.${body}.signature`;
}

describe("Apple response selection", () => {
  it("decodes a JWS payload that arrived inside an Apple response", () => {
    const decoded = decodeJwsPayload(jws({productId: "mevora_premium_monthly"}));
    assert.equal(decoded.productId, "mevora_premium_monthly");
  });

  it("returns null for anything that is not a JWS", () => {
    assert.equal(decodeJwsPayload("nope"), null);
    assert.equal(decodeJwsPayload("a.b"), null);
  });

  it("prefers a granting transaction over a lapsed one in the same group", () => {
    const selected = selectSubscriptionState({
      data: [
        {
          lastTransactions: [
            {
              status: 2,
              signedTransactionInfo: jws({
                productId: "mevora_premium_monthly",
                transactionId: "old",
              }),
              signedRenewalInfo: jws({autoRenewStatus: 0}),
            },
            {
              status: 1,
              signedTransactionInfo: jws({
                productId: "mevora_premium_yearly",
                transactionId: "live",
                expiresDate: EXPIRES,
              }),
              signedRenewalInfo: jws({autoRenewStatus: 1}),
            },
          ],
        },
      ],
    });
    // A lapsed transaction must not mask a live one.
    assert.equal(selected.transaction.transactionId, "live");
    assert.equal(selected.status, 1);
  });

  it("falls back to a non-granting transaction when that is all there is", () => {
    const selected = selectSubscriptionState({
      data: [
        {
          lastTransactions: [
            {
              status: 2,
              signedTransactionInfo: jws({transactionId: "expired"}),
            },
          ],
        },
      ],
    });
    assert.equal(selected.status, 2);
  });

  it("returns null when Apple sent nothing usable", () => {
    assert.equal(selectSubscriptionState({}), null);
    assert.equal(selectSubscriptionState({data: [{lastTransactions: []}]}), null);
  });
});

describe("Apple premium verification", () => {
  it("grants Premium only from what Apple reported", async () => {
    const store = memoryStore();
    const result = await verifyIosPremiumPurchase({
      userId: "user-1",
      transactionId: "1000000000000009",
      api: api({ok: true, state: appleState()}),
      now,
      makeStore: store.makeStore,
    });

    assert.equal(result.ok, true);
    assert.equal(result.isPremium, true);
    assert.equal(result.status, "active");
    assert.equal(store.box.writes, 1);
  });

  it("owns the subscription by its original transaction, not the latest", async () => {
    const store = memoryStore();
    await verifyIosPremiumPurchase({
      userId: "user-1",
      // A renewal presents a new transaction id.
      transactionId: "1000000000000099",
      api: api({ok: true, state: appleState()}),
      now,
      makeStore: store.makeStore,
    });

    // Keying on the latest id would make every renewal look unclaimed.
    assert.deepEqual(store.box.tokens, ["1000000000000001"]);
  });

  it("a fabricated transaction grants nothing", async () => {
    const store = memoryStore();
    const result = await verifyIosPremiumPurchase({
      userId: "user-1",
      transactionId: "made-up",
      api: api({ok: false, error: "invalid"}),
      now,
      makeStore: store.makeStore,
    });

    assert.equal(result.ok, false);
    assert.equal(result.isPremium, false);
    assert.equal(result.reason, "invalid");
    assert.equal(store.box.writes, 0);
  });

  it("another user cannot claim a subscription that is already owned", async () => {
    const result = await verifyIosPremiumPurchase({
      userId: "user-2",
      transactionId: "1000000000000009",
      api: api({ok: true, state: appleState()}),
      now,
      makeStore: conflictingStore,
    });

    assert.equal(result.ok, false);
    assert.equal(result.isPremium, false);
    assert.equal(result.reason, "owned_by_other");
  });

  it("a transaction from another app grants nothing", async () => {
    const store = memoryStore();
    const result = await verifyIosPremiumPurchase({
      userId: "user-1",
      transactionId: "1000000000000009",
      api: api({
        ok: true,
        state: appleState({transaction: {bundleId: "com.someone.else"}}),
      }),
      now,
      makeStore: store.makeStore,
    });

    assert.equal(result.ok, false);
    assert.equal(result.reason, "wrong_bundle");
    assert.equal(store.box.writes, 0);
  });

  it("a Boost product bought on iOS never becomes Premium", async () => {
    const store = memoryStore();
    const result = await verifyIosPremiumPurchase({
      userId: "user-1",
      transactionId: "1000000000000009",
      api: api({
        ok: true,
        state: appleState({transaction: {productId: "boost_week"}}),
      }),
      now,
      makeStore: store.makeStore,
    });

    assert.equal(result.ok, false);
    assert.equal(result.reason, "unknown_product");
    assert.equal(store.box.writes, 0);
  });

  it("a revoked subscription writes the loss rather than being ignored", async () => {
    const store = memoryStore();
    const result = await verifyIosPremiumPurchase({
      userId: "user-1",
      transactionId: "1000000000000009",
      api: api({
        ok: true,
        state: appleState({
          status: 5,
          transaction: {revocationDate: Date.parse("2026-09-27T11:00:00Z")},
        }),
      }),
      now,
      makeStore: store.makeStore,
    });

    assert.equal(result.ok, true);
    assert.equal(result.isPremium, false);
    assert.equal(result.status, "revoked");
  });

  it("an Apple outage is retryable and does not tear down entitlement", async () => {
    const store = memoryStore();
    await assert.rejects(
      () =>
        verifyIosPremiumPurchase({
          userId: "user-1",
          transactionId: "1000000000000009",
          api: api({ok: false, error: "transient"}),
          now,
          makeStore: store.makeStore,
        }),
      /store-unavailable|unavailable/,
    );
    assert.equal(store.box.writes, 0);
  });

  it("missing credentials grant nothing", async () => {
    const store = memoryStore();
    // Thrown, not answered, so the client keeps the transaction unfinished.
    await assert.rejects(
      () =>
        verifyIosPremiumPurchase({
          userId: "user-1",
          transactionId: "1000000000000009",
          api: api({ok: false, error: "unavailable"}),
          now,
          makeStore: store.makeStore,
        }),
      (error) => {
        assert.equal(error.code, "unavailable");
        return true;
      },
    );
    assert.equal(store.box.writes, 0);
  });
});
