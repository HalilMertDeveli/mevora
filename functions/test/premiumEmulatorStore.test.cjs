const {describe, it, beforeEach, afterEach} = require("node:test");
const assert = require("node:assert/strict");

const {
  EmulatorGoogleSubscriptionApi,
  EMULATOR_TOKEN_PREFIX,
  googleSubscriptionApi,
} = require("../lib/subscription/emulatorGoogleSubscriptionApi.js");
const {PlayDeveloperApi} = require("../lib/subscription/googleSubscriptionVerifier.js");
const {
  premiumCatalogue,
  EMULATOR_PREMIUM_PACKAGE,
} = require("../lib/subscription/productCatalog.js");
const {
  verifyAndroidPremiumPurchase,
} = require("../lib/subscription/verifyPremiumPurchase.js");
const {
  PurchaseOwnershipConflict,
} = require("../lib/subscription/premiumPurchaseStore.js");

const now = new Date("2026-09-28T12:00:00Z");
const token = (basePlan = "monthly") =>
  `${EMULATOR_TOKEN_PREFIX}mevora_premium:${basePlan}:123-1`;

const ENV_KEYS = [
  "FUNCTIONS_EMULATOR",
  "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON",
  "PREMIUM_ANDROID_PACKAGE_NAME",
  "PREMIUM_ANDROID_PRODUCT_IDS",
];
let saved;
beforeEach(() => {
  saved = Object.fromEntries(ENV_KEYS.map((key) => [key, process.env[key]]));
  for (const key of ENV_KEYS) delete process.env[key];
});
afterEach(() => {
  for (const key of ENV_KEYS) {
    if (saved[key] === undefined) delete process.env[key];
    else process.env[key] = saved[key];
  }
});

function memoryStore() {
  const box = {state: null, writes: 0};
  return {
    box,
    makeStore() {
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

describe("emulator test store — gating", () => {
  it("is selected only under the Functions emulator", () => {
    assert.ok(googleSubscriptionApi({}) instanceof PlayDeveloperApi);
    assert.ok(
      googleSubscriptionApi({FUNCTIONS_EMULATOR: "false"}) instanceof PlayDeveloperApi,
    );
    assert.ok(
      googleSubscriptionApi({FUNCTIONS_EMULATOR: "true"}) instanceof
        EmulatorGoogleSubscriptionApi,
    );
  });

  it("steps aside when a real Play credential is configured", () => {
    // With a credential the emulator talks to real Google, so a sandbox
    // purchase can still be tested locally against the real API.
    assert.ok(
      googleSubscriptionApi({
        FUNCTIONS_EMULATOR: "true",
        GOOGLE_PLAY_SERVICE_ACCOUNT_JSON: "{}",
      }) instanceof PlayDeveloperApi,
    );
  });

  it("an unconfigured catalogue stays empty outside the emulator", () => {
    const catalogue = premiumCatalogue({});
    assert.equal(catalogue.androidPackageName, "");
    assert.equal(catalogue.android.length, 0);
  });

  it("an unconfigured catalogue falls back to the emulator products inside it", () => {
    const catalogue = premiumCatalogue({FUNCTIONS_EMULATOR: "true"});
    assert.equal(catalogue.androidPackageName, EMULATOR_PREMIUM_PACKAGE);
    assert.deepEqual(
      catalogue.android.map((p) => `${p.productId}:${p.basePlanId}`),
      ["mevora_premium:monthly", "mevora_premium:yearly"],
    );
  });

  it("a configured catalogue wins even inside the emulator", () => {
    const catalogue = premiumCatalogue({
      FUNCTIONS_EMULATOR: "true",
      PREMIUM_ANDROID_PACKAGE_NAME: "com.mevora.app",
      PREMIUM_ANDROID_PRODUCT_IDS: "real_premium:monthly",
    });
    assert.equal(catalogue.androidPackageName, "com.mevora.app");
    assert.deepEqual(catalogue.android.map((p) => p.productId), ["real_premium"]);
  });

  it("the emulator package can never be the production one", () => {
    assert.match(EMULATOR_PREMIUM_PACKAGE, /emulator/);
  });
});

describe("emulator test store — answers", () => {
  const api = new EmulatorGoogleSubscriptionApi(() => now);

  it("refuses any token the test store did not mint", async () => {
    for (const bad of ["", "real-play-token", "emulator-test", "emulator-test:"]) {
      const result = await api.fetchSubscription({packageName: "x", purchaseToken: bad});
      assert.equal(result.ok, false, `accepted ${JSON.stringify(bad)}`);
    }
  });

  it("answers a minted token with an active sandbox subscription", async () => {
    const result = await api.fetchSubscription({
      packageName: "x",
      purchaseToken: token("monthly"),
    });
    assert.equal(result.ok, true);
    assert.equal(result.purchase.subscriptionState, "SUBSCRIPTION_STATE_ACTIVE");
    assert.ok(result.purchase.testPurchase, "must be marked as a test purchase");
    const item = result.purchase.lineItems[0];
    assert.equal(item.productId, "mevora_premium");
    assert.equal(item.offerDetails.basePlanId, "monthly");
    assert.equal(
      Date.parse(item.expiryTime) - now.getTime(),
      30 * 24 * 60 * 60 * 1000,
    );
  });

  it("a yearly plan runs for a year", async () => {
    const result = await api.fetchSubscription({
      packageName: "x",
      purchaseToken: token("yearly"),
    });
    assert.equal(
      Date.parse(result.purchase.lineItems[0].expiryTime) - now.getTime(),
      365 * 24 * 60 * 60 * 1000,
    );
  });
});

describe("emulator test purchase — full server path", () => {
  it("grants Premium through the real mapper, ownership and writer", async () => {
    process.env.FUNCTIONS_EMULATOR = "true";
    const store = memoryStore();
    const result = await verifyAndroidPremiumPurchase({
      userId: "qa-user-a",
      purchaseToken: token("monthly"),
      api: new EmulatorGoogleSubscriptionApi(() => now),
      now,
      makeStore: store.makeStore,
    });

    assert.equal(result.ok, true);
    assert.equal(result.isPremium, true);
    assert.equal(store.box.writes, 1);
    // Recorded as a test grant, never as a production purchase.
    assert.equal(store.box.state.storeEnvironment, "sandbox");
  });

  it("a second account presenting the same token is still refused", async () => {
    process.env.FUNCTIONS_EMULATOR = "true";
    const result = await verifyAndroidPremiumPurchase({
      userId: "qa-user-b",
      purchaseToken: token("monthly"),
      api: new EmulatorGoogleSubscriptionApi(() => now),
      now,
      makeStore: () => ({
        async transact() {
          throw new PurchaseOwnershipConflict("qa-user-a");
        },
      }),
    });

    assert.equal(result.ok, false);
    assert.equal(result.isPremium, false);
    assert.equal(result.reason, "owned_by_other");
  });

  it("a minted token grants nothing outside the emulator", async () => {
    // FUNCTIONS_EMULATOR unset: the catalogue is empty, so even a token the
    // test store minted is refused before any store is asked.
    const store = memoryStore();
    const result = await verifyAndroidPremiumPurchase({
      userId: "qa-user-a",
      purchaseToken: token("monthly"),
      api: new EmulatorGoogleSubscriptionApi(() => now),
      now,
      makeStore: store.makeStore,
    });

    assert.equal(result.ok, false);
    assert.equal(result.reason, "not_configured");
    assert.equal(store.box.writes, 0);
  });
});
