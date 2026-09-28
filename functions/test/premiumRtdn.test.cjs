const {describe, it, beforeEach} = require("node:test");
const assert = require("node:assert/strict");

const PKG = "com.mevora.app";
// The catalogue reads process.env at call time, so this must be set before the
// handler runs — not before the module is required.
process.env.PREMIUM_ANDROID_PACKAGE_NAME = PKG;
process.env.PREMIUM_ANDROID_PRODUCT_IDS = "mevora_premium:monthly,mevora_premium:yearly";

const {
  decodeNotification,
  tokenOf,
  handleDeveloperNotification,
} = require("../lib/subscription/googleRtdn.js");

const TOKEN = "token-abc";
const USER = "user-1";

function encode(notification) {
  return Buffer.from(JSON.stringify(notification), "utf8").toString("base64");
}

function notification(overrides = {}) {
  return {
    version: "1.0",
    packageName: PKG,
    eventTimeMillis: String(Date.parse("2026-09-27T12:00:00Z")),
    subscriptionNotification: {
      version: "1.0",
      notificationType: 2,
      purchaseToken: TOKEN,
      subscriptionId: "mevora_premium",
    },
    ...overrides,
  };
}

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

/** Records what the writer was handed, and replays a stored state. */
function makeHarness(options = {}) {
  const writes = [];
  let stored = options.stored ?? null;
  return {
    writes,
    get stored() {
      return stored;
    },
    persistenceFor() {
      return {
        async transact(userId, mutate) {
          const next = mutate(stored);
          writes.push({userId, next});
          if (next) {
            stored = next;
          }
          return stored ?? next;
        },
      };
    },
  };
}

function api(result) {
  let calls = 0;
  return {
    get calls() {
      return calls;
    },
    async fetchSubscription() {
      calls += 1;
      return result;
    },
  };
}

const owners = {
  async findOwner() {
    return USER;
  },
};

const noOwners = {
  async findOwner() {
    return null;
  },
};

describe("RTDN payload handling", () => {
  it("decodes a base64 Play notification", () => {
    const decoded = decodeNotification(encode(notification()));
    assert.equal(decoded.packageName, PKG);
    assert.equal(decoded.subscriptionNotification.purchaseToken, TOKEN);
  });

  it("returns null for anything that is not a notification", () => {
    assert.equal(decodeNotification("not-base64-json"), null);
    assert.equal(decodeNotification(Buffer.from("[]").toString("base64")).length, 0);
    assert.equal(decodeNotification(Buffer.from("null").toString("base64")), null);
  });

  it("finds the token on both subscription and voided notifications", () => {
    assert.equal(tokenOf(notification()), TOKEN);
    assert.equal(
      tokenOf({
        packageName: PKG,
        voidedPurchaseNotification: {purchaseToken: "voided-token"},
      }),
      "voided-token",
    );
    assert.equal(tokenOf({packageName: PKG}), null);
  });
});

describe("RTDN safety", () => {
  let harness;
  beforeEach(() => {
    harness = makeHarness();
  });

  it("refuses a notification for another package", async () => {
    const store = api({ok: true, purchase: purchase()});
    const result = await handleDeveloperNotification({
      notification: notification({packageName: "com.someone.else"}),
      api: store,
      owners,
      persistenceFor: harness.persistenceFor,
    });
    assert.equal(result.outcome, "rejected");
    assert.equal(result.reason, "wrong_package");
    // Never even asked Google about a token that is not ours.
    assert.equal(store.calls, 0);
    assert.equal(harness.writes.length, 0);
  });

  it("ignores a test notification without touching entitlement", async () => {
    const result = await handleDeveloperNotification({
      notification: {packageName: PKG, testNotification: {version: "1.0"}},
      api: api({ok: true, purchase: purchase()}),
      owners,
      persistenceFor: harness.persistenceFor,
    });
    assert.equal(result.outcome, "ignored");
    assert.equal(harness.writes.length, 0);
  });

  it("drops a token nobody has claimed rather than guessing a user", async () => {
    const result = await handleDeveloperNotification({
      notification: notification(),
      api: api({ok: true, purchase: purchase()}),
      owners: noOwners,
      persistenceFor: harness.persistenceFor,
    });
    assert.equal(result.outcome, "unattributed");
    assert.equal(harness.writes.length, 0);
  });

  it("asks for redelivery when Google is transiently unavailable", async () => {
    const result = await handleDeveloperNotification({
      notification: notification(),
      api: api({ok: false, error: "transient"}),
      owners,
      persistenceFor: harness.persistenceFor,
    });
    // A live entitlement must not be torn down because of an outage.
    assert.equal(result.outcome, "retry");
    assert.equal(harness.writes.length, 0);
  });

  it("does not write when Google says the token is not valid", async () => {
    const result = await handleDeveloperNotification({
      notification: notification(),
      api: api({ok: false, error: "not_found"}),
      owners,
      persistenceFor: harness.persistenceFor,
    });
    assert.equal(result.outcome, "rejected");
    assert.equal(harness.writes.length, 0);
  });

  it("reads state from the store, not from the notification type", async () => {
    // notificationType 3 is CANCELED, but the store says the subscription is
    // still active until its expiry. The store wins.
    const result = await handleDeveloperNotification({
      notification: notification({
        subscriptionNotification: {
          notificationType: 3,
          purchaseToken: TOKEN,
          subscriptionId: "mevora_premium",
        },
      }),
      api: api({ok: true, purchase: purchase()}),
      owners,
      persistenceFor: harness.persistenceFor,
    });
    assert.equal(result.outcome, "applied");
    assert.equal(harness.writes[0].next.status, "active");
    assert.equal(harness.writes[0].next.entitlement, "premium");
  });

  it("an expired subscription removes Premium", async () => {
    const result = await handleDeveloperNotification({
      notification: notification(),
      api: api({
        ok: true,
        purchase: purchase({subscriptionState: "SUBSCRIPTION_STATE_EXPIRED"}),
      }),
      owners,
      persistenceFor: harness.persistenceFor,
    });
    assert.equal(result.outcome, "applied");
    assert.equal(harness.writes[0].next.entitlement, "none");
  });

  it("a duplicate notification does not write twice", async () => {
    const shared = makeHarness();
    const payload = notification();
    const store = api({ok: true, purchase: purchase()});

    const first = await handleDeveloperNotification({
      notification: payload,
      api: store,
      owners,
      persistenceFor: shared.persistenceFor,
    });
    const second = await handleDeveloperNotification({
      notification: payload,
      api: store,
      owners,
      persistenceFor: shared.persistenceFor,
    });

    assert.equal(first.outcome, "applied");
    assert.equal(second.outcome, "applied");
    // At-least-once delivery is normal; the writer collapses the repeat.
    assert.equal(first.reason, "applied");
    assert.equal(second.reason, "noop");
  });

  it("an out-of-order notification cannot overwrite newer state", async () => {
    const shared = makeHarness();

    // The newer event lands first, as Pub/Sub is entitled to deliver it.
    await handleDeveloperNotification({
      notification: notification({
        eventTimeMillis: String(Date.parse("2026-09-27T12:00:00Z")),
      }),
      api: api({
        ok: true,
        purchase: purchase({subscriptionState: "SUBSCRIPTION_STATE_EXPIRED"}),
      }),
      owners,
      persistenceFor: shared.persistenceFor,
    });
    assert.equal(shared.stored.entitlement, "none");

    // Then a stale "active" message from before it arrives.
    const late = await handleDeveloperNotification({
      notification: notification({
        eventTimeMillis: String(Date.parse("2026-09-27T09:00:00Z")),
      }),
      api: api({ok: true, purchase: purchase()}),
      owners,
      persistenceFor: shared.persistenceFor,
    });

    assert.equal(late.reason, "stale_event");
    assert.equal(shared.stored.entitlement, "none");
  });

  it("a stale renewal cannot reopen a revoked entitlement", async () => {
    const shared = makeHarness();

    await handleDeveloperNotification({
      notification: notification({
        eventTimeMillis: String(Date.parse("2026-09-27T12:00:00Z")),
      }),
      api: api({
        ok: true,
        purchase: purchase({subscriptionState: "SUBSCRIPTION_STATE_CANCELED"}),
      }),
      owners,
      persistenceFor: shared.persistenceFor,
    });

    const before = shared.stored.entitlement;
    const late = await handleDeveloperNotification({
      notification: notification({
        eventTimeMillis: String(Date.parse("2026-09-26T12:00:00Z")),
      }),
      api: api({ok: true, purchase: purchase()}),
      owners,
      persistenceFor: shared.persistenceFor,
    });

    assert.equal(late.reason, "stale_event");
    assert.equal(shared.stored.entitlement, before);
  });

  it("a voided purchase follows the same path as any other message", async () => {
    const result = await handleDeveloperNotification({
      notification: {
        packageName: PKG,
        eventTimeMillis: String(Date.parse("2026-09-27T12:00:00Z")),
        voidedPurchaseNotification: {
          purchaseToken: TOKEN,
          orderId: "GPA.0001",
          productType: 1,
        },
      },
      api: api({
        ok: true,
        purchase: purchase({subscriptionState: "SUBSCRIPTION_STATE_EXPIRED"}),
      }),
      owners,
      persistenceFor: harness.persistenceFor,
    });
    assert.equal(result.outcome, "applied");
    assert.equal(harness.writes[0].next.entitlement, "none");
  });

  it("an unknown store state grants nothing", async () => {
    const result = await handleDeveloperNotification({
      notification: notification(),
      api: api({
        ok: true,
        purchase: purchase({subscriptionState: "SUBSCRIPTION_STATE_SOMETHING_NEW"}),
      }),
      owners,
      persistenceFor: harness.persistenceFor,
    });
    assert.equal(result.outcome, "rejected");
    assert.equal(result.reason, "unknown_state");
    assert.equal(harness.writes.length, 0);
  });

  it("a product outside the catalogue grants nothing", async () => {
    const result = await handleDeveloperNotification({
      notification: notification(),
      api: api({
        ok: true,
        purchase: purchase({
          lineItems: [
            {
              productId: "boost_week",
              expiryTime: "2026-10-27T12:00:00Z",
              offerDetails: {basePlanId: "weekly"},
            },
          ],
        }),
      }),
      owners,
      persistenceFor: harness.persistenceFor,
    });
    assert.equal(result.outcome, "rejected");
    assert.equal(harness.writes.length, 0);
  });
});
