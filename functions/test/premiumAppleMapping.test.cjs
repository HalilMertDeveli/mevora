const {describe, it} = require("node:test");
const assert = require("node:assert/strict");

const {
  mapAppleSubscription,
} = require("../lib/subscription/appleSubscriptionMapper.js");
const {evaluatePremiumAccess} = require("../lib/subscription/entitlementPolicy.js");

const BUNDLE = "com.mevora.app";
const CATALOGUE = {
  androidPackageName: "com.mevora.app",
  iosBundleId: BUNDLE,
  android: [{productId: "mevora_premium", basePlanId: "monthly", tier: "premium"}],
  ios: [
    {productId: "mevora_premium_monthly", basePlanId: null, tier: "premium"},
    {productId: "mevora_premium_yearly", basePlanId: null, tier: "premium"},
  ],
};

const eventAt = new Date("2026-09-27T12:00:00Z");
const EXPIRES = Date.parse("2026-10-27T12:00:00Z");

function state(overrides = {}) {
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

function map(overrides = {}) {
  return mapAppleSubscription({
    userId: "user-1",
    state: state(overrides),
    eventAt,
    catalogue: CATALOGUE,
  });
}

describe("Apple subscription mapping", () => {
  it("an active auto-renewing subscription grants Premium", () => {
    const result = map();
    assert.equal(result.ok, true);
    assert.equal(result.write.status, "active");
    assert.equal(result.write.entitlement, "premium");
    assert.equal(result.write.platform, "ios");
    assert.equal(result.write.autoRenewing, true);
    assert.equal(result.originalTransactionId, "1000000000000001");
  });

  it("identifies the subscription by its original transaction", () => {
    // Apple issues a new transaction id every renewal, so the latest one is
    // recorded but the original is what identifies the subscription.
    const result = map({transaction: {transactionId: "1000000000000042"}});
    assert.equal(result.write.latestPurchaseId, "1000000000000042");
    assert.equal(result.originalTransactionId, "1000000000000001");
  });

  it("auto-renew off is cancelled, and keeps access until expiry", () => {
    const result = map({renewal: {autoRenewStatus: 0}});
    assert.equal(result.write.status, "cancelled");
    assert.equal(result.write.entitlement, "premium");

    const access = evaluatePremiumAccess(
      {...result.write, revision: 1},
      new Date("2026-10-01T00:00:00Z"),
    );
    assert.equal(access.isPremium, true);
  });

  it("a cancelled subscription stops granting once it expires", () => {
    const result = map({renewal: {autoRenewStatus: 0}});
    const access = evaluatePremiumAccess(
      {...result.write, revision: 1},
      new Date("2026-11-01T00:00:00Z"),
    );
    assert.equal(access.isPremium, false);
  });

  it("grace period keeps access and carries Apple's own deadline", () => {
    const graceUntil = Date.parse("2026-11-03T12:00:00Z");
    const result = map({
      status: 4,
      renewal: {autoRenewStatus: 1, gracePeriodExpiresDate: graceUntil},
    });
    assert.equal(result.write.status, "grace_period");
    assert.equal(result.write.entitlement, "premium");
    assert.equal(result.write.graceUntil.getTime(), graceUntil);
  });

  it("billing retry keeps access, matching the store's own semantics", () => {
    const result = map({status: 3});
    assert.equal(result.write.status, "billing_retry");
    assert.equal(result.write.entitlement, "premium");
  });

  it("an expired subscription grants nothing", () => {
    const result = map({status: 2});
    assert.equal(result.write.status, "expired");
    assert.equal(result.write.entitlement, "none");
  });

  it("a revoked subscription loses Premium immediately", () => {
    const result = map({
      status: 5,
      transaction: {revocationDate: Date.parse("2026-09-27T11:00:00Z")},
    });
    assert.equal(result.write.status, "revoked");
    assert.equal(result.write.entitlement, "none");
  });

  it("a refund is distinguished from a revocation and also ends access", () => {
    const result = map({
      transaction: {
        revocationDate: Date.parse("2026-09-27T11:00:00Z"),
        revocationReason: 1,
      },
    });
    assert.equal(result.write.status, "refunded");
    assert.equal(result.write.entitlement, "none");
  });

  it("a revocation date overrides an active status", () => {
    // Apple can still report status 1 on the record that carries a revocation.
    // Money returned wins over a stale status field.
    const result = map({
      status: 1,
      transaction: {revocationDate: Date.parse("2026-09-27T11:00:00Z")},
    });
    assert.equal(result.write.entitlement, "none");
  });

  it("a transaction from another app grants nothing", () => {
    const result = map({transaction: {bundleId: "com.someone.else"}});
    assert.equal(result.ok, false);
    assert.equal(result.reason, "wrong_bundle");
  });

  it("a product outside the catalogue grants nothing", () => {
    const result = map({transaction: {productId: "boost_week"}});
    assert.equal(result.ok, false);
    assert.equal(result.reason, "unknown_product");
  });

  it("an unknown Apple status fails closed", () => {
    const result = map({status: 99});
    assert.equal(result.ok, false);
    assert.equal(result.reason, "unknown_state");
  });

  it("a missing status fails closed rather than defaulting to active", () => {
    const result = map({status: null});
    assert.equal(result.ok, false);
    assert.equal(result.reason, "unknown_state");
  });

  it("an unconfigured catalogue grants nothing", () => {
    const result = mapAppleSubscription({
      userId: "user-1",
      state: state(),
      eventAt,
      catalogue: {...CATALOGUE, ios: [], iosBundleId: ""},
    });
    assert.equal(result.ok, false);
    assert.equal(result.reason, "not_configured");
  });

  it("records the sandbox environment rather than assuming production", () => {
    const result = map({transaction: {environment: "Sandbox"}});
    assert.equal(result.write.storeEnvironment, "sandbox");
  });

  it("writes through the same canonical shape Google produces", () => {
    // Both stores must reach the writer with the same fields, so neither can
    // develop a private notion of what Premium means.
    const result = map();
    for (const field of [
      "userId",
      "status",
      "entitlement",
      "platform",
      "productId",
      "expiresAt",
      "autoRenewing",
      "storeEnvironment",
      "source",
      "eventAt",
    ]) {
      assert.ok(field in result.write, `missing ${field}`);
    }
    assert.equal(result.write.source, "store");
  });
});
