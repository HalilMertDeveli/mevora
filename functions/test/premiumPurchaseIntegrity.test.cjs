/**
 * Purchase-path integrity: what must be true before a client may acknowledge a
 * Premium purchase, which token an entitlement rests on, and how the Play
 * credential and RTDN delivery are configured.
 */
const {describe, it, before, after} = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const PKG = "com.mevora.app";
const saved = {};
before(() => {
  saved.pkg = process.env.PREMIUM_ANDROID_PACKAGE_NAME;
  saved.ids = process.env.PREMIUM_ANDROID_PRODUCT_IDS;
  process.env.PREMIUM_ANDROID_PACKAGE_NAME = PKG;
  process.env.PREMIUM_ANDROID_PRODUCT_IDS = "mevora_premium:monthly,mevora_premium:yearly";
});
after(() => {
  for (const [key, value] of [
    ["PREMIUM_ANDROID_PACKAGE_NAME", saved.pkg],
    ["PREMIUM_ANDROID_PRODUCT_IDS", saved.ids],
  ]) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
});

const {
  verifyAndroidPremiumPurchase,
  verifyIosPremiumPurchase,
  premiumAccountId,
} = require("../lib/subscription/verifyPremiumPurchase.js");
const {
  PlayDeveloperApi,
} = require("../lib/subscription/googleSubscriptionVerifier.js");
const {
  decideWrite,
} = require("../lib/subscription/entitlementWriter.js");
const {
  fromDocument,
  toDocument,
} = require("../lib/subscription/firestoreEntitlementStore.js");
const {
  purchaseTokenKey,
} = require("../lib/subscription/purchaseOwnership.js");
const {
  PurchaseOwnershipConflict,
} = require("../lib/subscription/premiumPurchaseStore.js");
const {
  handleDeveloperNotification,
  isTooOldToRetry,
  RTDN_MAX_RETRY_AGE_MS,
} = require("../lib/subscription/googleRtdn.js");

const now = new Date("2026-10-01T12:00:00Z");

/** One user's entitlement document, shared by every token that user owns. */
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

const api = (result) => ({
  async fetchSubscription() {
    return result;
  },
});

function purchase(overrides = {}) {
  return {
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    latestOrderId: "GPA.1",
    lineItems: [
      {
        productId: "mevora_premium",
        expiryTime: "2026-11-01T12:00:00Z",
        autoRenewingPlan: {autoRenewEnabled: true},
        offerDetails: {basePlanId: "monthly"},
      },
    ],
    ...overrides,
  };
}

function expired(overrides = {}) {
  return purchase({
    subscriptionState: "SUBSCRIPTION_STATE_EXPIRED",
    lineItems: [
      {
        productId: "mevora_premium",
        expiryTime: "2026-09-30T12:00:00Z",
        offerDetails: {basePlanId: "monthly"},
      },
    ],
    ...overrides,
  });
}

function verify(overrides = {}) {
  const store = overrides.store ?? memoryStore();
  return verifyAndroidPremiumPurchase({
    userId: overrides.userId ?? "u1",
    purchaseToken: overrides.token ?? "tok-1",
    api: overrides.api ?? api({ok: true, purchase: purchase()}),
    now: overrides.now ?? now,
    makeStore: () => overrides.persistence ?? store.persistence,
  }).then((result) => ({result, store}));
}

describe("D3 — a purchase nobody could verify is never answered as handled", () => {
  it("a missing Play credential is a retryable error, not a result", async () => {
    const store = memoryStore();
    await assert.rejects(
      () => verify({store, api: api({ok: false, error: "unavailable"})}),
      (error) => {
        // Not `ok:false`: a client that completes on any answer would
        // acknowledge a purchase that granted nothing.
        assert.equal(error.code, "unavailable");
        return true;
      },
    );
    assert.equal(store.box.writes, 0);
  });

  it("an unconfigured catalogue is a retryable error, not a result", async () => {
    const pkg = process.env.PREMIUM_ANDROID_PACKAGE_NAME;
    const ids = process.env.PREMIUM_ANDROID_PRODUCT_IDS;
    process.env.PREMIUM_ANDROID_PACKAGE_NAME = "";
    process.env.PREMIUM_ANDROID_PRODUCT_IDS = "";
    const store = memoryStore();
    try {
      await assert.rejects(
        () => verify({store}),
        (error) => {
          assert.equal(error.code, "failed-precondition");
          return true;
        },
      );
      assert.equal(store.box.writes, 0);
    } finally {
      process.env.PREMIUM_ANDROID_PACKAGE_NAME = pkg;
      process.env.PREMIUM_ANDROID_PRODUCT_IDS = ids;
    }
  });

  it("the Apple path answers the same way when it is not configured", async () => {
    // No PREMIUM_IOS_* in this suite, so the iOS catalogue is empty.
    await assert.rejects(
      () =>
        verifyIosPremiumPurchase({
          userId: "u1",
          transactionId: "1000000000000001",
          api: {
            async fetchSubscription() {
              throw new Error("must not be asked");
            },
          },
          now,
          makeStore: () => memoryStore().persistence,
        }),
      (error) => {
        assert.equal(error.code, "failed-precondition");
        return true;
      },
    );
  });

  it("a definitive rejection is still an answer", async () => {
    const {result, store} = await verify({api: api({ok: false, error: "invalid"})});
    assert.equal(result.ok, false);
    assert.equal(result.reason, "invalid");
    assert.equal(store.box.writes, 0);
  });
});

describe("D3 — Play credential problems are not mistaken for a bad token", () => {
  const lookup = (status, body = {}) =>
    new PlayDeveloperApi({
      accessToken: async () => "access-token",
      fetchImpl: async () => ({
        ok: status >= 200 && status < 300,
        status,
        async json() {
          return body;
        },
      }),
    }).fetchSubscription({packageName: PKG, purchaseToken: "tok-1"});

  it("401 and 403 mean the service account is not authorised", async () => {
    // Google saying "you may not ask" is about Mevora's credential, not about
    // the purchase. Reporting it as `invalid` would end a real purchase.
    for (const status of [401, 403]) {
      assert.deepEqual(await lookup(status), {ok: false, error: "unavailable"});
    }
  });

  it("other 4xx still mean the token is not valid", async () => {
    for (const status of [400, 404, 410]) {
      assert.deepEqual(await lookup(status), {ok: false, error: "invalid"});
    }
  });

  it("5xx and 429 stay transient", async () => {
    for (const status of [429, 500, 503]) {
      assert.deepEqual(await lookup(status), {ok: false, error: "transient"});
    }
  });

  it("no credential at all fails closed", async () => {
    const result = await new PlayDeveloperApi({
      accessToken: async () => null,
      fetchImpl: async () => {
        throw new Error("must not be called without a credential");
      },
    }).fetchSubscription({packageName: PKG, purchaseToken: "tok-1"});
    assert.deepEqual(result, {ok: false, error: "unavailable"});
  });
});

describe("D9 — a superseded token cannot take away what another token grants", () => {
  const OLD = "token-monthly";
  const NEW = "token-yearly";

  it("an upgrade survives the old token's expiry notification", async () => {
    const store = memoryStore();
    const owners = {
      async findOwner() {
        return "u1";
      },
    };

    await verify({store, token: OLD});
    // The upgrade: a new token that names the old one as its predecessor.
    await verify({
      store,
      token: NEW,
      now: new Date("2026-10-01T12:05:00Z"),
      api: api({
        ok: true,
        purchase: purchase({
          linkedPurchaseToken: OLD,
          lineItems: [
            {
              productId: "mevora_premium",
              expiryTime: "2027-10-01T12:05:00Z",
              autoRenewingPlan: {autoRenewEnabled: true},
              offerDetails: {basePlanId: "yearly"},
            },
          ],
        }),
      }),
    });
    assert.equal(store.box.state.isPremium, true);

    // Play then reports the replaced token as expired — later than the upgrade.
    const result = await handleDeveloperNotification({
      notification: {
        packageName: PKG,
        eventTimeMillis: String(Date.parse("2026-10-01T12:06:00Z")),
        subscriptionNotification: {notificationType: 13, purchaseToken: OLD},
      },
      api: api({ok: true, purchase: expired()}),
      owners,
      persistenceFor: () => store.persistence,
      now: new Date("2026-10-01T12:06:00Z"),
    });

    assert.equal(result.outcome, "applied");
    assert.equal(result.reason, "superseded_token");
    assert.equal(store.box.state.status, "active");
    assert.equal(store.box.state.isPremium, true);
    assert.equal(store.box.state.purchaseTokenKey, purchaseTokenKey(NEW));
  });

  const granting = (key) => ({
    userId: "u1",
    platform: "android",
    productId: "mevora_premium",
    status: "active",
    entitlement: "premium",
    originalTransactionId: null,
    latestPurchaseId: "GPA.2",
    expiresAt: new Date("2026-11-01T12:00:00Z"),
    graceUntil: null,
    autoRenewing: true,
    lastVerifiedAt: now,
    storeEnvironment: "production",
    source: "store",
    revision: 0,
    eventAt: new Date("2026-10-01T11:00:00Z"),
    isPremium: true,
    purchaseTokenKey: key,
  });

  const lapse = (extra = {}) => ({
    userId: "u1",
    status: "expired",
    entitlement: "none",
    platform: "android",
    productId: "mevora_premium",
    expiresAt: new Date("2026-09-30T12:00:00Z"),
    eventAt: now,
    ...extra,
  });

  it("refuses a lapse reported by a token the entitlement does not rest on", () => {
    const decision = decideWrite(
      granting("key-current"),
      lapse({purchaseTokenKey: "key-old"}),
      now,
    );
    assert.equal(decision.outcome, "superseded_token");
    assert.equal(decision.applied, false);
    assert.equal(decision.state.isPremium, true);
  });

  it("the entitlement's own token can still end it", () => {
    const decision = decideWrite(
      granting("key-current"),
      lapse({purchaseTokenKey: "key-current"}),
      now,
    );
    assert.equal(decision.outcome, "applied");
    assert.equal(decision.state.isPremium, false);
  });

  it("the successor in an upgrade chain speaks for the subscription", () => {
    // The replacement is the live subscription now, whatever state it is in.
    const decision = decideWrite(
      granting("key-current"),
      lapse({
        status: "billing_retry",
        entitlement: "premium",
        purchaseTokenKey: "key-next",
        supersedesTokenKey: "key-current",
      }),
      now,
    );
    assert.equal(decision.outcome, "applied");
    assert.equal(decision.state.purchaseTokenKey, "key-next");
  });

  it("a different token that grants takes the entitlement over", () => {
    const decision = decideWrite(
      granting("key-current"),
      {
        userId: "u1",
        status: "active",
        entitlement: "premium",
        platform: "android",
        productId: "mevora_premium",
        expiresAt: new Date("2027-10-01T12:00:00Z"),
        eventAt: now,
        purchaseTokenKey: "key-other",
      },
      now,
    );
    assert.equal(decision.outcome, "applied");
    assert.equal(decision.state.purchaseTokenKey, "key-other");
    assert.equal(decision.state.isPremium, true);
  });

  it("nothing is protected once the stored entitlement has itself run out", () => {
    const stale = {
      ...granting("key-current"),
      expiresAt: new Date("2026-09-01T00:00:00Z"),
    };
    const decision = decideWrite(stale, lapse({purchaseTokenKey: "key-old"}), now);
    assert.equal(decision.outcome, "applied");
  });

  it("documents written before the token was recorded behave as before", () => {
    const legacy = {...granting(null)};
    const decision = decideWrite(legacy, lapse({purchaseTokenKey: "key-old"}), now);
    assert.equal(decision.outcome, "applied");
    assert.equal(decision.state.isPremium, false);
  });

  it("the token key round-trips through Firestore and is never undefined", () => {
    const doc = toDocument(granting("key-current"));
    assert.equal(doc.purchaseTokenKey, "key-current");
    const legacyDoc = toDocument({...granting(null), purchaseTokenKey: undefined});
    assert.equal(legacyDoc.purchaseTokenKey, null);
    for (const [field, value] of Object.entries(legacyDoc)) {
      assert.notEqual(value, undefined, `${field} must not be undefined`);
    }
    assert.equal(fromDocument("u1", doc).purchaseTokenKey, "key-current");
    assert.equal(fromDocument("u1", {status: "active"}).purchaseTokenKey, null);
  });
});

describe("D11 — a purchase made for one account cannot be claimed by another", () => {
  const withAccount = (id) =>
    api({
      ok: true,
      purchase: purchase({
        externalAccountIdentifiers: {obfuscatedExternalAccountId: id},
      }),
    });

  it("the account id is a hash, never the uid", () => {
    const id = premiumAccountId("u1");
    assert.equal(id, createHash("sha256").update("u1").digest("hex"));
    assert.equal(id.length, 64, "Play accepts at most 64 characters");
    // The app computes the same value; its test pins the same literal.
    assert.equal(
      premiumAccountId("user-1"),
      "c6c289e49e9c05b2145860387b73bcb18df43fb09a1e4a4a9713c76c88bb541b",
    );
  });

  it("grants when the purchase names this account", async () => {
    const {result, store} = await verify({api: withAccount(premiumAccountId("u1"))});
    assert.equal(result.ok, true);
    assert.equal(result.isPremium, true);
    assert.equal(store.box.writes, 1);
  });

  it("refuses a purchase that names a different account", async () => {
    const {result, store} = await verify({
      userId: "u2",
      api: withAccount(premiumAccountId("u1")),
    });
    assert.equal(result.ok, false);
    assert.equal(result.isPremium, false);
    assert.equal(result.reason, "account_mismatch");
    assert.equal(store.box.writes, 0, "nothing may be claimed or written");
  });

  it("still accepts a purchase that names nobody", async () => {
    // Bought by an older build, or resubscribed from the Play Store itself.
    const {result} = await verify({api: withAccount(null)});
    assert.equal(result.ok, true);
    assert.equal(result.isPremium, true);
  });
});

describe("D6 — RTDN redelivery", () => {
  const owners = {
    async findOwner() {
      return "u1";
    },
  };
  const notification = {
    packageName: PKG,
    eventTimeMillis: String(now.getTime()),
    subscriptionNotification: {notificationType: 2, purchaseToken: "tok-1"},
  };

  it("a missing or unauthorised credential asks for redelivery", async () => {
    // An event dropped while the credential is being fixed is a renewal or a
    // refund Mevora never hears about.
    const result = await handleDeveloperNotification({
      notification,
      api: api({ok: false, error: "unavailable"}),
      owners,
      persistenceFor: () => memoryStore().persistence,
      now,
    });
    assert.equal(result.outcome, "retry");
  });

  it("an ownership conflict is acknowledged, not thrown", async () => {
    const result = await handleDeveloperNotification({
      notification,
      api: api({ok: true, purchase: purchase()}),
      owners,
      persistenceFor: () => ({
        async transact() {
          throw new PurchaseOwnershipConflict("someone-else");
        },
      }),
      now,
    });
    assert.equal(result.outcome, "rejected");
    assert.equal(result.reason, "owned_by_other");
  });

  it("gives up on an event that has been retried for too long", () => {
    const born = new Date(now.getTime() - RTDN_MAX_RETRY_AGE_MS - 1000);
    assert.equal(isTooOldToRetry(born.toISOString(), now), true);
    assert.equal(isTooOldToRetry(now.toISOString(), now), false);
    // An unreadable time must not turn into an endless retry.
    assert.equal(isTooOldToRetry(undefined, now), false);
    assert.equal(isTooOldToRetry("not-a-date", now), false);
  });
});

describe("D4 / D6 — deployed configuration", () => {
  const SECRET = "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON";
  const secretsOf = (fn) =>
    (fn.__endpoint.secretEnvironmentVariables ?? []).map((entry) => entry.key);

  const MODULES = [
    "../lib/googlePlayConfig.js",
    "../lib/subscription/verifyPremiumPurchase.js",
    "../lib/subscription/googleRtdnFunction.js",
    "../lib/boost/verifyBoostPurchase.js",
  ];
  let savedEmulator;

  /** Re-requires the function modules as a deployment or as the emulator. */
  function load({emulator}) {
    if (emulator) process.env.FUNCTIONS_EMULATOR = "true";
    else delete process.env.FUNCTIONS_EMULATOR;
    for (const name of MODULES) delete require.cache[require.resolve(name)];
    return {
      ...require("../lib/subscription/verifyPremiumPurchase.js"),
      ...require("../lib/subscription/googleRtdnFunction.js"),
      ...require("../lib/boost/verifyBoostPurchase.js"),
    };
  }

  before(() => {
    savedEmulator = process.env.FUNCTIONS_EMULATOR;
    process.env.FIREBASE_CONFIG ??= JSON.stringify({projectId: "demo-premium"});
    process.env.GCLOUD_PROJECT ??= "demo-premium";
    const admin = require("firebase-admin");
    if (admin.apps.length === 0) {
      admin.initializeApp({projectId: "demo-premium"});
    }
  });
  after(() => {
    if (savedEmulator === undefined) delete process.env.FUNCTIONS_EMULATOR;
    else process.env.FUNCTIONS_EMULATOR = savedEmulator;
  });

  it("verifyPremiumPurchase binds the Play service account secret", () => {
    const {verifyPremiumPurchase} = load({emulator: false});
    assert.ok(secretsOf(verifyPremiumPurchase).includes(SECRET));
  });

  it("the RTDN function binds the secret and asks Pub/Sub to retry", () => {
    const {onPlaySubscriptionNotification} = load({emulator: false});
    assert.ok(secretsOf(onPlaySubscriptionNotification).includes(SECRET));
    assert.equal(
      onPlaySubscriptionNotification.__endpoint.eventTrigger.retry,
      true,
      "throwing only redelivers when the trigger is declared retryable",
    );
  });

  it("verifyBoostPurchase binds the secret; activateBoost does not need it", () => {
    const boost = load({emulator: false});
    assert.ok(secretsOf(boost.verifyBoostPurchase).includes(SECRET));
    assert.ok(!secretsOf(boost.activateBoost).includes(SECRET));
  });

  it("the emulator is never handed the secret", () => {
    // The emulator fills a bound secret from Secret Manager when it can, and
    // the emulator test stores only answer while no credential is present.
    const fns = load({emulator: true});
    for (const name of [
      "verifyPremiumPurchase",
      "onPlaySubscriptionNotification",
      "verifyBoostPurchase",
    ]) {
      assert.deepEqual(secretsOf(fns[name]), [], `${name} binds a secret in the emulator`);
    }
  });

  it(".env.example names every Play variable and holds no credential", () => {
    const example = fs.readFileSync(path.join(__dirname, "..", ".env.example"), "utf8");
    for (const name of [
      SECRET,
      "ANDROID_PACKAGE_NAME",
      "PREMIUM_ANDROID_PACKAGE_NAME",
      "PREMIUM_ANDROID_PRODUCT_IDS",
      "PREMIUM_RTDN_TOPIC",
    ]) {
      assert.ok(example.includes(name), `${name} is not documented`);
    }
    assert.ok(
      !new RegExp(`^\\s*${SECRET}\\s*=\\s*\\S`, "m").test(example),
      "the service account must never be given a value in an env file",
    );
    assert.ok(!example.includes("private_key"));
  });
});
