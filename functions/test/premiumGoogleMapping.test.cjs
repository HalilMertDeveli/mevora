const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  resolveAndroidProduct,
  resolveIosProduct,
} = require("../lib/subscription/productCatalog.js");
const {
  mapGoogleSubscription,
} = require("../lib/subscription/googleSubscriptionMapper.js");
const {
  purchaseTokenKey,
  resolveInheritedOwner,
} = require("../lib/subscription/purchaseOwnership.js");
const {evaluatePremiumAccess} = require("../lib/subscription/entitlementPolicy.js");

const PKG = "com.mevora.app";
const CATALOGUE = {
  androidPackageName: PKG,
  iosBundleId: "com.mevora.app",
  android: [
    {productId: "mevora_premium", basePlanId: "monthly", tier: "premium"},
    {productId: "mevora_premium", basePlanId: "yearly", tier: "premium"},
  ],
  ios: [{productId: "mevora_premium_monthly", basePlanId: null, tier: "premium"}],
};

const eventAt = new Date("2026-09-27T12:00:00Z");

function purchase(overrides = {}) {
  return {
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    latestOrderId: "GPA.0001",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    lineItems: [
      {
        productId: "mevora_premium",
        expiryTime: "2026-10-27T12:00:00Z",
        autoRenewingPlan: {autoRenewEnabled: true},
        offerDetails: {basePlanId: "monthly"},
      },
    ],
    ...overrides,
  };
}

function map(overrides = {}, catalogue = CATALOGUE) {
  return mapGoogleSubscription({
    userId: "u1",
    packageName: PKG,
    purchase: purchase(overrides),
    eventAt,
    catalogue,
  });
}

describe("premium product catalogue — fail closed", () => {
  it("an unconfigured catalogue grants nothing", () => {
    const empty = {androidPackageName: "", iosBundleId: "", android: [], ios: []};
    assert.deepEqual(
      resolveAndroidProduct({packageName: PKG, productId: "mevora_premium"}, empty),
      {ok: false, reason: "not_configured"},
    );
    assert.deepEqual(
      resolveIosProduct({bundleId: "com.mevora.app", productId: "x"}, empty),
      {ok: false, reason: "not_configured"},
    );
  });

  it("a foreign package cannot claim our products", () => {
    const res = resolveAndroidProduct(
      {packageName: "com.attacker.app", productId: "mevora_premium", basePlanId: "monthly"},
      CATALOGUE,
    );
    assert.deepEqual(res, {ok: false, reason: "package_mismatch"});
  });

  it("an unlisted product grants nothing", () => {
    const res = resolveAndroidProduct(
      {packageName: PKG, productId: "mevora_boost_7_days", basePlanId: "monthly"},
      CATALOGUE,
    );
    assert.deepEqual(res, {ok: false, reason: "unknown_product"});
  });

  it("a known product on an unlisted base plan grants nothing", () => {
    const res = resolveAndroidProduct(
      {packageName: PKG, productId: "mevora_premium", basePlanId: "lifetime-free"},
      CATALOGUE,
    );
    assert.deepEqual(res, {ok: false, reason: "unknown_base_plan"});
  });
});

describe("google subscription state mapping", () => {
  const cases = [
    ["SUBSCRIPTION_STATE_ACTIVE", "active", "premium"],
    ["SUBSCRIPTION_STATE_CANCELED", "cancelled", "premium"],
    ["SUBSCRIPTION_STATE_IN_GRACE_PERIOD", "grace_period", "premium"],
    ["SUBSCRIPTION_STATE_ON_HOLD", "billing_retry", "premium"],
    ["SUBSCRIPTION_STATE_PAUSED", "paused", "none"],
    ["SUBSCRIPTION_STATE_PENDING", "pending", "none"],
    ["SUBSCRIPTION_STATE_EXPIRED", "expired", "none"],
    ["SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED", "expired", "none"],
  ];

  for (const [googleState, status, entitlement] of cases) {
    it(`${googleState} maps to ${status}/${entitlement}`, () => {
      const res = map({subscriptionState: googleState});
      assert.equal(res.ok, true);
      assert.equal(res.write.status, status);
      assert.equal(res.write.entitlement, entitlement);
    });
  }

  it("an unknown state is rejected rather than guessed", () => {
    assert.deepEqual(map({subscriptionState: "SUBSCRIPTION_STATE_UNSPECIFIED"}), {
      ok: false,
      reason: "unknown_state",
    });
    assert.deepEqual(map({subscriptionState: "SOMETHING_GOOGLE_ADDS_LATER"}), {
      ok: false,
      reason: "unknown_state",
    });
  });

  it("a purchase with no line item is rejected", () => {
    assert.deepEqual(map({lineItems: []}), {ok: false, reason: "no_line_item"});
    assert.deepEqual(map({lineItems: null}), {ok: false, reason: "no_line_item"});
  });

  it("a Boost product can never grant Premium", () => {
    const res = map({
      lineItems: [
        {
          productId: "mevora_boost_7_days",
          expiryTime: "2026-10-27T12:00:00Z",
          offerDetails: {basePlanId: "monthly"},
        },
      ],
    });
    assert.deepEqual(res, {ok: false, reason: "unknown_product"});
  });

  it("a test purchase is recorded as sandbox, not production", () => {
    const res = map({testPurchase: {}});
    assert.equal(res.write.storeEnvironment, "sandbox");
    assert.equal(map().write.storeEnvironment, "production");
  });

  it("carries the linked purchase token and acknowledgement state out", () => {
    const res = map({
      linkedPurchaseToken: "old-token",
      acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
    });
    assert.equal(res.linkedPurchaseToken, "old-token");
    assert.equal(res.acknowledged, false);
    assert.equal(map().acknowledged, true);
  });

  it("uses the latest expiry across line items", () => {
    const res = map({
      lineItems: [
        {
          productId: "mevora_premium",
          expiryTime: "2026-10-01T00:00:00Z",
          offerDetails: {basePlanId: "monthly"},
        },
        {
          productId: "mevora_premium",
          expiryTime: "2026-11-01T00:00:00Z",
          offerDetails: {basePlanId: "monthly"},
        },
      ],
    });
    assert.equal(res.write.expiresAt.toISOString(), "2026-11-01T00:00:00.000Z");
  });
});

describe("mapped state resolves to the intended access", () => {
  const now = new Date("2026-09-28T00:00:00Z");

  const resolve = (googleState) => {
    const res = map({subscriptionState: googleState});
    assert.equal(res.ok, true);
    return evaluatePremiumAccess(
      {
        userId: "u1",
        status: res.write.status,
        entitlement: res.write.entitlement,
        expiresAt: res.write.expiresAt,
        graceUntil: res.write.graceUntil,
      },
      now,
    );
  };

  it("active and cancelled-with-time-left keep access", () => {
    assert.equal(resolve("SUBSCRIPTION_STATE_ACTIVE").isPremium, true);
    assert.equal(resolve("SUBSCRIPTION_STATE_CANCELED").isPremium, true);
  });

  it("grace keeps access while the window is open", () => {
    assert.equal(resolve("SUBSCRIPTION_STATE_IN_GRACE_PERIOD").isPremium, true);
  });

  it("paused, pending and expired never grant access", () => {
    assert.equal(resolve("SUBSCRIPTION_STATE_PAUSED").isPremium, false);
    assert.equal(resolve("SUBSCRIPTION_STATE_PENDING").isPremium, false);
    assert.equal(resolve("SUBSCRIPTION_STATE_EXPIRED").isPremium, false);
  });

  it("account hold with no open window denies access", () => {
    // Google on-hold: the line item expiry is already in the past.
    const res = map({
      subscriptionState: "SUBSCRIPTION_STATE_ON_HOLD",
      lineItems: [
        {
          productId: "mevora_premium",
          expiryTime: "2026-09-01T00:00:00Z",
          offerDetails: {basePlanId: "monthly"},
        },
      ],
    });
    const access = evaluatePremiumAccess(
      {
        userId: "u1",
        status: res.write.status,
        entitlement: res.write.entitlement,
        expiresAt: res.write.expiresAt,
        graceUntil: res.write.graceUntil,
      },
      now,
    );
    assert.equal(access.isPremium, false);
  });
});

describe("purchase token ownership", () => {
  it("hashes the token instead of using it as a document id", () => {
    const key = purchaseTokenKey("super-secret-play-token");
    assert.match(key, /^[0-9a-f]{64}$/);
    assert.ok(!key.includes("super-secret"));
  });

  it("is stable for the same token and distinct across tokens", () => {
    assert.equal(purchaseTokenKey("a"), purchaseTokenKey("a"));
    assert.notEqual(purchaseTokenKey("a"), purchaseTokenKey("b"));
  });

  it("a replacement token inherits only its own previous owner", () => {
    assert.equal(
      resolveInheritedOwner({linkedOwnerUserId: "u1", claimantUserId: "u1"}),
      "inherit_ok",
    );
    assert.equal(
      resolveInheritedOwner({linkedOwnerUserId: "u1", claimantUserId: "u2"}),
      "owned_by_other",
    );
    assert.equal(
      resolveInheritedOwner({linkedOwnerUserId: null, claimantUserId: "u1"}),
      "no_link",
    );
  });
});
