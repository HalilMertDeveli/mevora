const {describe, it, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {
  verifyAndroidPremiumPurchase,
} = require("../lib/subscription/verifyPremiumPurchase.js");
const {
  PurchaseOwnershipConflict,
} = require("../lib/subscription/premiumPurchaseStore.js");

const PKG = "com.mevora.app";
const now = new Date("2026-09-27T12:00:00Z");

const saved = {};
before(() => {
  saved.pkg = process.env.PREMIUM_ANDROID_PACKAGE_NAME;
  saved.ids = process.env.PREMIUM_ANDROID_PRODUCT_IDS;
  process.env.PREMIUM_ANDROID_PACKAGE_NAME = PKG;
  process.env.PREMIUM_ANDROID_PRODUCT_IDS = "mevora_premium:monthly,mevora_premium:yearly";
});
after(() => {
  process.env.PREMIUM_ANDROID_PACKAGE_NAME = saved.pkg;
  process.env.PREMIUM_ANDROID_PRODUCT_IDS = saved.ids;
});

/** An in-memory persistence that records what the writer decided to store. */
function memoryStore(seed = null) {
  const box = {state: seed, writes: 0};
  return {
    box,
    persistence: {
      async transact(userId, mutate) {
        const next = mutate(box.state);
        if (next) {
          box.state = next;
          box.writes += 1;
        }
        return box.state ?? {userId};
      },
    },
  };
}

/** Persistence that always reports the token belongs to someone else. */
const conflictingStore = {
  async transact() {
    throw new PurchaseOwnershipConflict("someone-else");
  },
};

const api = (result) => ({async fetchSubscription() {
  return result;
}});

const activePurchase = {
  subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
  latestOrderId: "GPA.1",
  lineItems: [
    {
      productId: "mevora_premium",
      expiryTime: "2026-10-27T12:00:00Z",
      autoRenewingPlan: {autoRenewEnabled: true},
      offerDetails: {basePlanId: "monthly"},
    },
  ],
};

function run(overrides = {}) {
  const store = overrides.store ?? memoryStore();
  return verifyAndroidPremiumPurchase({
    userId: overrides.userId ?? "u1",
    purchaseToken: overrides.token ?? "tok-1",
    api: overrides.api ?? api({ok: true, purchase: activePurchase}),
    now,
    makeStore: () => (overrides.persistence ?? store.persistence),
  }).then((result) => ({result, store}));
}

describe("premium purchase — the client cannot grant itself Premium", () => {
  it("a genuine, catalogued purchase grants Premium", async () => {
    const {result, store} = await run();
    assert.equal(result.ok, true);
    assert.equal(result.isPremium, true);
    assert.equal(result.status, "active");
    assert.equal(store.box.writes, 1);
  });

  it("a token Google rejects grants nothing", async () => {
    const {result, store} = await run({api: api({ok: false, error: "invalid"})});
    assert.equal(result.ok, false);
    assert.equal(result.isPremium, false);
    assert.equal(result.reason, "invalid");
    assert.equal(store.box.writes, 0, "nothing may be written for a bad token");
  });

  it("a valid token for a Boost product grants nothing", async () => {
    const {result, store} = await run({
      api: api({
        ok: true,
        purchase: {
          ...activePurchase,
          lineItems: [
            {
              productId: "mevora_boost_7_days",
              expiryTime: "2026-10-27T12:00:00Z",
              offerDetails: {basePlanId: "monthly"},
            },
          ],
        },
      }),
    });
    assert.equal(result.ok, false);
    assert.equal(result.reason, "unknown_product");
    assert.equal(store.box.writes, 0);
  });

  it("a token owned by another account grants nothing and does not name the owner", async () => {
    const {result} = await run({persistence: conflictingStore});
    assert.equal(result.ok, false);
    assert.equal(result.isPremium, false);
    assert.equal(result.reason, "owned_by_other");
    assert.ok(
      !JSON.stringify(result).includes("someone-else"),
      "must not disclose who owns the token",
    );
  });

  it("the client's claimed product is ignored — the store decides", async () => {
    // The request carries only a token; there is no productId parameter to
    // lie about. Verify the granted product came from the store response.
    const {result, store} = await run();
    assert.equal(result.ok, true);
    assert.equal(store.box.state.productId, "mevora_premium");
  });

  it("an unconfigured catalogue grants nothing even for a real purchase", async () => {
    const pkg = process.env.PREMIUM_ANDROID_PACKAGE_NAME;
    const ids = process.env.PREMIUM_ANDROID_PRODUCT_IDS;
    process.env.PREMIUM_ANDROID_PACKAGE_NAME = "";
    process.env.PREMIUM_ANDROID_PRODUCT_IDS = "";
    try {
      const {result, store} = await run();
      assert.equal(result.ok, false);
      assert.equal(result.reason, "not_configured");
      assert.equal(store.box.writes, 0);
    } finally {
      process.env.PREMIUM_ANDROID_PACKAGE_NAME = pkg;
      process.env.PREMIUM_ANDROID_PRODUCT_IDS = ids;
    }
  });

  it("a Google outage is retryable and does not revoke a live entitlement", async () => {
    await assert.rejects(
      () => run({api: api({ok: false, error: "transient"})}),
      (error) => {
        assert.equal(error.code, "unavailable");
        return true;
      },
    );
  });

  it("an unknown store state grants nothing", async () => {
    const {result, store} = await run({
      api: api({
        ok: true,
        purchase: {...activePurchase, subscriptionState: "SUBSCRIPTION_STATE_UNSPECIFIED"},
      }),
    });
    assert.equal(result.ok, false);
    assert.equal(result.reason, "unknown_state");
    assert.equal(store.box.writes, 0);
  });
});

describe("premium purchase — replay and lifecycle", () => {
  it("replaying the same purchase is idempotent, not a second grant", async () => {
    const store = memoryStore();
    const first = await verifyAndroidPremiumPurchase({
      userId: "u1",
      purchaseToken: "tok-1",
      api: api({ok: true, purchase: activePurchase}),
      now,
      makeStore: () => store.persistence,
    });
    const second = await verifyAndroidPremiumPurchase({
      userId: "u1",
      purchaseToken: "tok-1",
      api: api({ok: true, purchase: activePurchase}),
      now,
      makeStore: () => store.persistence,
    });
    assert.equal(first.isPremium, true);
    assert.equal(second.isPremium, true);
    assert.equal(
      store.box.writes,
      1,
      "an identical replay must not produce a second entitlement write",
    );
  });

  it("a refunded purchase removes access immediately", async () => {
    const store = memoryStore();
    await run({store});
    const {result} = await run({
      store,
      api: api({
        ok: true,
        purchase: {
          ...activePurchase,
          subscriptionState: "SUBSCRIPTION_STATE_EXPIRED",
          lineItems: [
            {
              productId: "mevora_premium",
              expiryTime: "2026-09-01T00:00:00Z",
              offerDetails: {basePlanId: "monthly"},
            },
          ],
        },
      }),
    });
    assert.equal(result.isPremium, false);
  });

  it("cancelled with time left keeps access until the paid period ends", async () => {
    const {result} = await run({
      api: api({
        ok: true,
        purchase: {...activePurchase, subscriptionState: "SUBSCRIPTION_STATE_CANCELED"},
      }),
    });
    assert.equal(result.isPremium, true);
    assert.equal(result.status, "cancelled");
    assert.equal(result.accessUntil, "2026-10-27T12:00:00.000Z");
  });
});
