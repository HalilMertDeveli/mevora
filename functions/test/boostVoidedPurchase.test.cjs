/**
 * A Boost purchase Google voids — refunded, charged back, revoked — stops
 * being a grant.
 *
 * The ledger entry is marked voided and only what the member has not used yet
 * is taken back: the part of a time-boxed Boost that still lies ahead, or the
 * wallet credits that are still there. Time another purchase paid for stays,
 * a wallet never goes below zero, and hearing about the same void twice
 * changes nothing.
 */
const {after, before, beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const {Timestamp} = require("firebase-admin/firestore");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs} = require("./helpers/adminStubs.cjs");

const fake = createFakeFirestore();
let autoId = 0;
const db = {
  ...fake,
  // The double has neither auto ids nor add(); the grant and sendUserPush need both.
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

const {grantBoostPurchase} = require("../lib/boost/verifyBoostPurchase.js");
const {ApplePurchaseVerifier} = require("../lib/boost/applePurchaseVerifier.js");
const {GooglePurchaseVerifier} = require("../lib/boost/googlePurchaseVerifier.js");
const {PurchaseVerificationService} = require("../lib/boost/purchaseVerificationService.js");
const {voidBoostPurchase} = require("../lib/boost/voidedPurchases.js");
const {handleBoostDeveloperNotification} = require("../lib/boost/boostRtdn.js");
const {sweepVoidedBoostPurchases, VOIDED_SWEEP_LOOKBACK_MS} = require("../lib/boost/voidedPurchaseSweep.js");

const PKG = "com.mevora.app";
const WEEK = "mevora_boost_7_days";
const FIVE_PACK = "com.mevora.app.boost.5";
const DAY_MS = 24 * 60 * 60 * 1000;
const WEEK_MS = 7 * DAY_MS;
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

const ledgerPath = (token) => `purchases/android_${sha256(token)}`;
const ledger = (token) => fake.read(ledgerPath(token));
const boostPaths = (uid) => fake.paths().filter((path) => path.startsWith(`users/${uid}/boosts/`));
const boostOf = (uid) => fake.read(boostPaths(uid)[0]);
const balance = (uid) => fake.read(`users/${uid}/boostWallet/current`)?.balance ?? 0;
const daysLeft = (uid) => (boostOf(uid).expiresAt.toMillis() - Date.now()) / DAY_MS;
const near = (actual, expected, tolerance = 0.01) =>
  assert.ok(Math.abs(actual - expected) <= tolerance, `expected about ${expected}, got ${actual}`);
const noUndefined = (value, at = "document") => {
  assert.notEqual(value, undefined, `${at} must not be undefined`);
  if (value && typeof value === "object" && !(value instanceof Timestamp)) {
    for (const [key, inner] of Object.entries(value)) noUndefined(inner, `${at}.${key}`);
  }
};

/** A verifier that accepts any token: the ledger rules are what is under test. */
const verification = new PurchaseVerificationService(new ApplePurchaseVerifier(), new GooglePurchaseVerifier());
let orderSeq = 0;
const buy = (uid, purchaseToken, productId = WEEK) =>
  grantBoostPurchase({
    db,
    uid,
    payload: {platform: "android", productId, transactionId: `GPA.order-${++orderSeq}`, purchaseToken},
    verification,
  });
const voidToken = (purchaseToken, overrides = {}) =>
  voidBoostPurchase(db, {purchaseToken, source: "rtdn_voided", ...overrides});

/** A week bought `boughtDaysAgo` days ago, on a Boost that ends in `endsInDays` days. */
function weekBought({uid = "u1", token, boughtDaysAgo, endsInDays, boostId = "b1", recorded = true, status = "active"}) {
  const boughtAt = Timestamp.fromMillis(Date.now() - boughtDaysAgo * DAY_MS);
  const expiresAt = Timestamp.fromMillis(Date.now() + endsInDays * DAY_MS);
  return {
    [ledgerPath(token)]: {
      purchaseId: `android_${sha256(token)}`,
      userId: uid,
      productId: WEEK,
      boostCount: 0,
      durationDays: 7,
      durationMs: WEEK_MS,
      platform: "android",
      transactionId: "GPA.3300-0000-0000-00001",
      purchaseTokenHashOrReference: sha256(token),
      status: "verified",
      purchasedAt: boughtAt,
      verifiedAt: boughtAt,
      createdAt: boughtAt,
      ...(recorded ? {boostId, boostExpiresAt: expiresAt} : {}),
    },
    [`users/${uid}/boosts/${boostId}`]: {
      boostId,
      userId: uid,
      productId: WEEK,
      purchaseId: `android_${sha256(token)}`,
      status,
      startedAt: boughtAt,
      expiresAt,
      createdAt: boughtAt,
    },
  };
}

const saved = {};
before(() => {
  saved.emulator = process.env.FUNCTIONS_EMULATOR;
  saved.account = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON;
  // The emulator verifier accepts any token, so a grant needs no Play double.
  process.env.FUNCTIONS_EMULATOR = "true";
  delete process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON;
});
after(() => {
  for (const [key, name] of [["emulator", "FUNCTIONS_EMULATOR"], ["account", "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"]]) {
    if (saved[key] === undefined) delete process.env[name];
    else process.env[name] = saved[key];
  }
});
beforeEach(() => {
  fake.reset({});
  autoId = 0;
});

describe("voided Boost purchase — a time-boxed Boost", () => {
  it("a grant records which Boost it paid for and until when", async () => {
    const result = await buy("u1", "t1");

    const entry = ledger("t1");
    assert.equal(entry.boostId, result.boost.boostId);
    assert.equal(entry.boostExpiresAt.toMillis(), boostOf("u1").expiresAt.toMillis());
    noUndefined(entry, "ledger");
  });

  it("voided straight away: the ledger is voided and the Boost ends", async () => {
    await buy("u1", "t1");

    const result = await voidToken("t1", {orderId: "GPA.1", voidedReason: 1, voidedSource: 0});

    assert.equal(result.outcome, "voided");
    const entry = ledger("t1");
    assert.equal(entry.status, "voided");
    assert.ok(entry.voidedAt instanceof Timestamp);
    const boost = boostOf("u1");
    assert.equal(boost.status, "cancelled");
    assert.equal(boost.endedReason, "purchase_voided");
    assert.ok(boost.expiresAt.toMillis() <= Date.now() + 1000, "an ended Boost has no time left");
  });

  it("writes an audit record of what was taken back, with no undefined field", async () => {
    await buy("u1", "raw-play-token");
    const before = boostOf("u1").expiresAt.toMillis();

    await voidToken("raw-play-token", {
      orderId: "GPA.1",
      voidedReason: 7,
      voidedSource: 2,
      voidedAt: new Date(1790000000000),
    });

    const entry = ledger("raw-play-token");
    const audit = entry.void;
    noUndefined(entry, "ledger");
    assert.equal(audit.source, "rtdn_voided");
    assert.equal(audit.orderId, "GPA.1");
    assert.equal(audit.voidedReason, 7);
    assert.equal(audit.voidedSource, 2);
    assert.equal(audit.storeVoidedAt.toMillis(), 1790000000000);
    assert.equal(audit.statusBefore, "verified");
    assert.equal(audit.boostId, boostPaths("u1")[0].split("/").pop());
    assert.equal(audit.boostEnded, true);
    assert.equal(audit.boostExpiresAtBefore.toMillis(), before);
    near(audit.revokedDurationMs / DAY_MS, 7);
    assert.equal(audit.revokedCredits, 0);
    assert.ok(!JSON.stringify(entry).includes("raw-play-token"), "the raw token is never stored");
  });

  it("an audit record without store details stores nulls, not undefined", async () => {
    await buy("u1", "t1");

    await voidToken("t1");

    const audit = ledger("t1").void;
    noUndefined(audit, "void");
    assert.equal(audit.orderId, null);
    assert.equal(audit.voidedReason, null);
    assert.equal(audit.storeVoidedAt, null);
  });

  it("partly used: only the days still ahead are taken back", async () => {
    fake.reset(weekBought({token: "t1", boughtDaysAgo: 3, endsInDays: 4}));

    const result = await voidToken("t1");

    assert.equal(result.outcome, "voided");
    assert.equal(boostOf("u1").status, "cancelled");
    near(ledger("t1").void.revokedDurationMs / DAY_MS, 4);
  });

  it("already run out: the ledger is voided and nothing else changes", async () => {
    fake.reset(weekBought({token: "t1", boughtDaysAgo: 10, endsInDays: -3, status: "expired"}));
    const boostBefore = boostOf("u1");

    const result = await voidToken("t1");

    assert.equal(result.outcome, "voided");
    assert.equal(ledger("t1").status, "voided");
    assert.equal(ledger("t1").void.revokedDurationMs, 0);
    assert.equal(ledger("t1").void.boostId, null);
    assert.deepEqual(boostOf("u1"), boostBefore);
  });

  it("never takes time a later purchase paid for", async () => {
    // The first week ran out; a second, separate week is running now.
    fake.reset({
      ...weekBought({token: "old", boughtDaysAgo: 10, endsInDays: -3, boostId: "b1", status: "expired"}),
      ...weekBought({token: "new", boughtDaysAgo: 1, endsInDays: 6, boostId: "b2"}),
    });

    await voidToken("old");

    const running = fake.read("users/u1/boosts/b2");
    assert.equal(running.status, "active");
    near((running.expiresAt.toMillis() - Date.now()) / DAY_MS, 6);
    assert.equal(ledger("old").void.revokedDurationMs, 0);
    assert.equal(ledger("new").status, "verified");
  });

  it("two stacked weeks: voiding the first leaves the second week", async () => {
    await buy("u1", "t1");
    await buy("u1", "t2");
    near(daysLeft("u1"), 14);

    await voidToken("t1");

    assert.equal(boostOf("u1").status, "active");
    near(daysLeft("u1"), 7);
    assert.equal(ledger("t1").void.boostEnded, false);
    assert.equal(ledger("t2").status, "verified");
  });

  it("two stacked weeks: voiding the second leaves the first week", async () => {
    await buy("u1", "t1");
    await buy("u1", "t2");

    await voidToken("t2");

    assert.equal(boostOf("u1").status, "active");
    near(daysLeft("u1"), 7);
  });

  it("two stacked weeks, both voided in either order: the Boost ends, never before now", async () => {
    for (const order of [["t1", "t2"], ["t2", "t1"]]) {
      fake.reset({});
      await buy("u1", "t1");
      await buy("u1", "t2");

      await voidToken(order[0]);
      await voidToken(order[1]);

      const boost = boostOf("u1");
      assert.equal(boost.status, "cancelled", order.join(" then "));
      near((boost.expiresAt.toMillis() - Date.now()) / DAY_MS, 0);
      assert.ok(boost.expiresAt.toMillis() >= boost.startedAt.toMillis(), "a Boost cannot end before it began");
    }
  });

  it("an entry from before the Boost was recorded falls back to its purchase date", async () => {
    fake.reset(weekBought({token: "t1", boughtDaysAgo: 3, endsInDays: 4, recorded: false}));

    await voidToken("t1");

    assert.equal(boostOf("u1").status, "cancelled");
    near(ledger("t1").void.revokedDurationMs / DAY_MS, 4);
  });

  it("an unrecorded entry that was stacked is under-revoked rather than guessed at", async () => {
    // Bought 3 days ago on top of an earlier week, so the Boost still has 11
    // days. Without a record of where this week sits, only what its own
    // purchase date can account for (4 days) is taken.
    fake.reset(weekBought({token: "t1", boughtDaysAgo: 3, endsInDays: 11, recorded: false}));

    await voidToken("t1");

    assert.equal(boostOf("u1").status, "active");
    near(daysLeft("u1"), 7);
  });
});

describe("voided Boost purchase — wallet credits", () => {
  it("unused credits are removed", async () => {
    await buy("u1", "pack", FIVE_PACK);
    assert.equal(balance("u1"), 5);

    const result = await voidToken("pack");

    assert.equal(result.outcome, "voided");
    assert.equal(balance("u1"), 0);
    const audit = ledger("pack").void;
    assert.equal(audit.revokedCredits, 5);
    assert.equal(audit.balanceBefore, 5);
    assert.equal(audit.balanceAfter, 0);
    assert.equal(audit.revokedDurationMs, 0);
    noUndefined(ledger("pack"), "ledger");
  });

  it("credits already spent are not taken again: the wallet stops at zero", async () => {
    await buy("u1", "pack", FIVE_PACK);
    await db.doc("users/u1/boostWallet/current").set({balance: 2}, {merge: true});

    await voidToken("pack");

    assert.equal(balance("u1"), 0);
    assert.equal(ledger("pack").void.revokedCredits, 2);
  });

  it("an empty wallet stays at zero", async () => {
    await buy("u1", "pack", FIVE_PACK);
    await db.doc("users/u1/boostWallet/current").set({balance: 0}, {merge: true});

    await voidToken("pack");

    assert.equal(balance("u1"), 0);
    assert.equal(ledger("pack").void.revokedCredits, 0);
    assert.equal(ledger("pack").status, "voided");
  });

  it("a second pack's credits survive", async () => {
    await buy("u1", "pack-a", FIVE_PACK);
    await buy("u1", "pack-b", FIVE_PACK);

    await voidToken("pack-a");

    assert.equal(balance("u1"), 5);
    assert.equal(ledger("pack-b").status, "verified");
  });

  it("a voided pack does not end a running Boost", async () => {
    await buy("u1", "week");
    await buy("u1", "pack", FIVE_PACK);

    await voidToken("pack");

    assert.equal(boostOf("u1").status, "active");
    near(daysLeft("u1"), 7);
  });
});

describe("voided Boost purchase — idempotency and identity", () => {
  it("the same void twice revokes once", async () => {
    await buy("u1", "pack-a", FIVE_PACK);
    await buy("u1", "pack-b", FIVE_PACK);

    const first = await voidToken("pack-a");
    const voidedAt = ledger("pack-a").voidedAt.toMillis();
    const second = await voidToken("pack-a", {source: "voided_purchases_api"});

    assert.equal(first.outcome, "voided");
    assert.equal(second.outcome, "alreadyVoided");
    assert.equal(balance("u1"), 5, "the second void must not take the other pack's credits");
    assert.equal(ledger("pack-a").voidedAt.toMillis(), voidedAt);
    assert.equal(ledger("pack-a").void.source, "rtdn_voided", "the first record stands");
  });

  it("two simultaneous voids revoke once", async () => {
    await buy("u1", "pack-a", FIVE_PACK);
    await buy("u1", "pack-b", FIVE_PACK);

    const results = await Promise.all([voidToken("pack-a"), voidToken("pack-a")]);

    assert.deepEqual(results.map((result) => result.outcome).sort(), ["alreadyVoided", "voided"]);
    assert.equal(balance("u1"), 5);
  });

  it("a token that was never granted writes nothing", async () => {
    await buy("u1", "t1");
    const pathsBefore = fake.paths();

    const result = await voidToken("someone-elses-token");

    assert.equal(result.outcome, "notFound");
    assert.deepEqual(fake.paths(), pathsBefore);
    assert.equal(ledger("t1").status, "verified");
  });

  it("finds an entry written before the token became the ledger key", async () => {
    const seeded = weekBought({token: "t1", boughtDaysAgo: 1, endsInDays: 6});
    const legacyPath = "purchases/android_GPA.3300-0000-0000-00001";
    fake.reset({
      [legacyPath]: {...seeded[ledgerPath("t1")], purchaseId: "android_GPA.3300-0000-0000-00001"},
      "users/u1/boosts/b1": seeded["users/u1/boosts/b1"],
    });

    const result = await voidToken("t1");

    assert.equal(result.outcome, "voided");
    assert.equal(fake.read(legacyPath).status, "voided");
    assert.equal(boostOf("u1").status, "cancelled");
  });

  it("only the buyer's Boost is touched", async () => {
    await buy("u1", "t1");
    await buy("u2", "t2");

    await voidToken("t1");

    assert.equal(boostOf("u2").status, "active");
    near(daysLeft("u2"), 7);
  });

  it("a voided token is never granted again — to its buyer or to anyone else", async () => {
    await buy("u1", "t1");
    await voidToken("t1");
    const rejectedWith = (code) => (error) => {
      assert.equal(error.code, code);
      return true;
    };

    // The emulator verifier would accept the token; the ledger must not.
    await assert.rejects(buy("u1", "t1"), rejectedWith("invalid-argument"));
    await assert.rejects(buy("u2", "t1"), rejectedWith("already-exists"));

    assert.equal(ledger("t1").status, "voided");
    assert.equal(boostPaths("u1").length, 1);
    assert.equal(boostOf("u1").status, "cancelled");
    assert.deepEqual(boostPaths("u2"), []);
  });
});

describe("Play notifications about one-time purchases", () => {
  const message = (overrides = {}) => ({
    version: "1.0",
    packageName: PKG,
    eventTimeMillis: "1790000000000",
    ...overrides,
  });
  const voided = (purchaseToken, fields = {}) =>
    message({voidedPurchaseNotification: {purchaseToken, orderId: "GPA.1", productType: 2, refundType: 1, ...fields}});
  const oneTime = (purchaseToken, notificationType) =>
    message({oneTimeProductNotification: {version: "1.0", notificationType, purchaseToken, sku: WEEK}});
  const handle = (notification) =>
    handleBoostDeveloperNotification({notification, voidPurchase: (input) => voidBoostPurchase(db, input)});

  it("a voided one-time purchase revokes the Boost it bought", async () => {
    await buy("u1", "t1");

    const result = await handle(voided("t1"));

    assert.deepEqual(result, {outcome: "applied", reason: "voided"});
    assert.equal(ledger("t1").status, "voided");
    assert.equal(ledger("t1").void.source, "rtdn_voided");
    assert.equal(ledger("t1").void.orderId, "GPA.1");
    assert.equal(ledger("t1").void.storeVoidedAt.toMillis(), 1790000000000);
    assert.equal(boostOf("u1").status, "cancelled");
  });

  it("does not depend on Premium being configured", async () => {
    const savedPremium = {
      pkg: process.env.PREMIUM_ANDROID_PACKAGE_NAME,
      ids: process.env.PREMIUM_ANDROID_PRODUCT_IDS,
    };
    delete process.env.PREMIUM_ANDROID_PACKAGE_NAME;
    delete process.env.PREMIUM_ANDROID_PRODUCT_IDS;
    try {
      await buy("u1", "t1");
      assert.equal((await handle(voided("t1"))).outcome, "applied");
    } finally {
      if (savedPremium.pkg !== undefined) process.env.PREMIUM_ANDROID_PACKAGE_NAME = savedPremium.pkg;
      if (savedPremium.ids !== undefined) process.env.PREMIUM_ANDROID_PRODUCT_IDS = savedPremium.ids;
    }
  });

  it("a redelivered notification is acknowledged and changes nothing", async () => {
    await buy("u1", "pack-a", FIVE_PACK);
    await buy("u1", "pack-b", FIVE_PACK);
    await handle(voided("pack-a"));

    const again = await handle(voided("pack-a"));

    assert.deepEqual(again, {outcome: "applied", reason: "already_voided"});
    assert.equal(balance("u1"), 5);
  });

  it("a one-time void for a token nobody was granted is acknowledged, not retried", async () => {
    assert.deepEqual(await handle(voided("unknown")), {outcome: "unattributed", reason: "no_boost_purchase"});
  });

  it("a partial, quantity-based refund revokes nothing", async () => {
    await buy("u1", "t1");

    const result = await handle(voided("t1", {refundType: 2}));

    assert.deepEqual(result, {outcome: "ignored", reason: "partial_refund"});
    assert.equal(ledger("t1").status, "verified");
    assert.equal(boostOf("u1").status, "active");
  });

  it("another app's notification never reaches the ledger", async () => {
    await buy("u1", "t1");

    const result = await handle({...voided("t1"), packageName: "com.someone.else"});

    assert.deepEqual(result, {outcome: "rejected", reason: "wrong_package"});
    assert.equal(ledger("t1").status, "verified");
  });

  it("leaves subscription messages to the Premium handler", async () => {
    await buy("u1", "t1");

    assert.equal(await handle(voided("sub-token", {productType: 1})), null);
    assert.equal(
      await handle(message({subscriptionNotification: {notificationType: 2, purchaseToken: "sub-token"}})),
      null,
    );
    assert.equal(await handle(message({testNotification: {version: "1.0"}})), null);
    // No product type and no Boost entry: it may be a subscription's.
    assert.equal(await handle(voided("sub-token", {productType: undefined})), null);
    assert.equal(ledger("t1").status, "verified");
  });

  it("a void that names no product type still revokes a Boost token", async () => {
    await buy("u1", "t1");

    const result = await handle(voided("t1", {productType: undefined}));

    assert.equal(result.outcome, "applied");
    assert.equal(ledger("t1").status, "voided");
  });

  it("a completed one-time purchase needs nothing: the app submits it", async () => {
    await buy("u1", "t1");

    assert.deepEqual(await handle(oneTime("t1", 1)), {outcome: "ignored", reason: "one_time_purchased"});
    assert.equal(ledger("t1").status, "verified");
  });

  it("a cancelled one-time purchase revokes a grant if there ever was one", async () => {
    await buy("u1", "t1");

    assert.deepEqual(await handle(oneTime("never-granted", 2)), {
      outcome: "unattributed",
      reason: "no_boost_purchase",
    });
    assert.deepEqual(await handle(oneTime("t1", 2)), {outcome: "applied", reason: "voided"});
    assert.equal(ledger("t1").void.source, "rtdn_one_time_canceled");
  });

  it("a notification without a token is acknowledged", async () => {
    assert.deepEqual(await handle(voided("")), {outcome: "ignored", reason: "no_token"});
  });

  it("a ledger failure surfaces, so Pub/Sub redelivers", async () => {
    await assert.rejects(
      handleBoostDeveloperNotification({
        notification: voided("t1"),
        voidPurchase: async () => {
          throw new Error("firestore unavailable");
        },
      }),
      /firestore unavailable/,
    );
  });

  describe("through the Pub/Sub trigger", () => {
    const {onPlaySubscriptionNotification} = require("../lib/subscription/googleRtdnFunction.js");
    const deliver = (notification, time = new Date().toISOString()) =>
      onPlaySubscriptionNotification.run({
        time,
        data: {message: {data: Buffer.from(JSON.stringify(notification), "utf8").toString("base64")}},
      });

    it("a voided Boost purchase is revoked without asking Play about a subscription", async () => {
      await buy("u1", "t1");

      await deliver(voided("t1"));

      assert.equal(ledger("t1").status, "voided");
      assert.equal(boostOf("u1").status, "cancelled");
    });

    it("an unknown one-time token is acknowledged", async () => {
      await deliver(voided("unknown"));
      await deliver(oneTime("unknown", 1));
    });
  });
});

describe("Voided Purchases API sweep — the fallback when no notification arrives", () => {
  /** `purchases.voidedpurchases.list`, in memory, two results to a page. */
  function fakePlay(voidedPurchases, {status = 200} = {}) {
    const play = {
      calls: [],
      fetch: async (url, init = {}) => {
        const parsed = new URL(String(url));
        play.calls.push({
          path: parsed.pathname,
          query: Object.fromEntries(parsed.searchParams),
          authorization: init.headers?.Authorization,
        });
        if (status !== 200) {
          return {ok: false, status, json: async () => ({})};
        }
        const start = Number(parsed.searchParams.get("token") ?? 0);
        const page = voidedPurchases.slice(start, start + 2);
        const next = start + 2 < voidedPurchases.length ? String(start + 2) : null;
        return {
          ok: true,
          status: 200,
          json: async () => ({
            voidedPurchases: page,
            ...(next ? {tokenPagination: {nextPageToken: next}} : {}),
          }),
        };
      },
    };
    return play;
  }
  const entry = (purchaseToken, fields = {}) => ({
    kind: "androidpublisher#voidedPurchase",
    purchaseToken,
    orderId: `GPA.${purchaseToken}`,
    purchaseTimeMillis: "1789000000000",
    voidedTimeMillis: "1790000000000",
    voidedSource: 0,
    voidedReason: 1,
    ...fields,
  });
  const sweep = (play, now = new Date()) =>
    sweepVoidedBoostPurchases(db, {
      play: new GooglePurchaseVerifier({accessToken: async () => "play-access", fetch: play.fetch}),
      now,
    });

  // Purchases are made against the emulator verifier; the sweep itself runs
  // as a deployment, where the Play double answers.
  const asDeployment = () => delete process.env.FUNCTIONS_EMULATOR;
  const asEmulator = () => {
    process.env.FUNCTIONS_EMULATOR = "true";
  };
  beforeEach(asEmulator);

  it("revokes every voided purchase on the ledger, across pages", async () => {
    await buy("u1", "t1");
    await buy("u2", "pack", FIVE_PACK);
    await buy("u3", "t3");
    asDeployment();
    const play = fakePlay([entry("t1"), entry("not-ours"), entry("pack", {voidedReason: 7, voidedSource: 2})]);

    const result = await sweep(play);
    asEmulator();

    assert.deepEqual(result, {seen: 3, voided: 2, alreadyVoided: 0, unknown: 1, pages: 2, complete: true});
    assert.equal(ledger("t1").status, "voided");
    assert.equal(ledger("t1").void.source, "voided_purchases_api");
    assert.equal(ledger("t1").void.orderId, "GPA.t1");
    assert.equal(ledger("t1").void.storeVoidedAt.toMillis(), 1790000000000);
    assert.equal(boostOf("u1").status, "cancelled");
    assert.equal(balance("u2"), 0);
    assert.equal(ledger("pack").void.voidedReason, 7);
    assert.equal(ledger("t3").status, "verified");
    assert.equal(boostOf("u3").status, "active");
  });

  it("asks Play for one-time purchases only, inside the 30 days it keeps", async () => {
    asDeployment();
    const play = fakePlay([entry("a"), entry("b"), entry("c")]);
    const now = new Date(1790000000000);

    await sweep(play, now);
    asEmulator();

    assert.equal(play.calls.length, 2);
    const [first, second] = play.calls;
    assert.equal(first.path, `/androidpublisher/v3/applications/${PKG}/purchases/voidedpurchases`);
    assert.equal(first.authorization, "Bearer play-access");
    assert.equal(first.query.type, "0");
    assert.equal(Number(first.query.startTime), now.getTime() - VOIDED_SWEEP_LOOKBACK_MS);
    assert.ok(VOIDED_SWEEP_LOOKBACK_MS < 30 * DAY_MS, "Play refuses a start time older than 30 days");
    assert.equal(first.query.token, undefined);
    assert.equal(second.query.token, "2");
  });

  it("running it again changes nothing", async () => {
    await buy("u1", "pack-a", FIVE_PACK);
    await buy("u1", "pack-b", FIVE_PACK);
    asDeployment();
    const play = fakePlay([entry("pack-a")]);

    await sweep(play);
    const again = await sweep(play);
    asEmulator();

    assert.deepEqual(again, {seen: 1, voided: 0, alreadyVoided: 1, unknown: 0, pages: 1, complete: true});
    assert.equal(balance("u1"), 5);
  });

  it("a notification and the sweep for the same purchase revoke once", async () => {
    await buy("u1", "pack-a", FIVE_PACK);
    await buy("u1", "pack-b", FIVE_PACK);
    await voidToken("pack-a");
    asDeployment();

    const result = await sweep(fakePlay([entry("pack-a")]));
    asEmulator();

    assert.equal(result.alreadyVoided, 1);
    assert.equal(balance("u1"), 5);
    assert.equal(ledger("pack-a").void.source, "rtdn_voided");
  });

  it("a Play failure revokes nothing and reports the sweep as incomplete", async () => {
    await buy("u1", "t1");
    asDeployment();

    const result = await sweep(fakePlay([entry("t1")], {status: 503}));
    asEmulator();

    assert.equal(result.complete, false);
    assert.equal(result.voided, 0);
    assert.equal(ledger("t1").status, "verified");
  });

  it("without a Play credential it does nothing", async () => {
    await buy("u1", "t1");
    asDeployment();
    let fetched = 0;

    const result = await sweepVoidedBoostPurchases(db, {
      play: new GooglePurchaseVerifier({
        accessToken: async () => null,
        fetch: async () => {
          fetched += 1;
          return {ok: true, status: 200, json: async () => ({})};
        },
      }),
    });
    asEmulator();

    assert.equal(result.complete, false);
    assert.equal(fetched, 0);
    assert.equal(ledger("t1").status, "verified");
  });

  it("the emulator has no Play to ask and never calls out", async () => {
    await buy("u1", "t1");
    asEmulator();
    let fetched = 0;

    const result = await sweepVoidedBoostPurchases(db, {
      play: new GooglePurchaseVerifier({
        fetch: async () => {
          fetched += 1;
          return {ok: true, status: 200, json: async () => ({})};
        },
      }),
    });

    assert.equal(fetched, 0);
    assert.equal(result.seen, 0);
    assert.equal(ledger("t1").status, "verified");
  });

  describe("the scheduled function", () => {
    const SECRET = "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON";
    const MODULES = ["../lib/googlePlayConfig.js", "../lib/boost/voidedPurchaseSweep.js"];
    const secretsOf = (fn) => (fn.__endpoint.secretEnvironmentVariables ?? []).map((item) => item.key);
    function load({emulator}) {
      if (emulator) asEmulator();
      else asDeployment();
      for (const name of MODULES) delete require.cache[require.resolve(name)];
      const loaded = require("../lib/boost/voidedPurchaseSweep.js");
      asEmulator();
      return loaded;
    }

    it("is exported for deployment", () => {
      const source = require("node:fs").readFileSync(require("node:path").join(__dirname, "..", "src", "index.ts"), "utf8");
      assert.match(source, /reconcileVoidedBoostPurchases/);
    });

    it("binds the Play secret when deployed and never in the emulator", () => {
      assert.ok(secretsOf(load({emulator: false}).reconcileVoidedBoostPurchases).includes(SECRET));
      assert.deepEqual(secretsOf(load({emulator: true}).reconcileVoidedBoostPurchases), []);
    });

    it("runs daily in the functions region", () => {
      const {reconcileVoidedBoostPurchases} = load({emulator: true});
      assert.equal(reconcileVoidedBoostPurchases.__endpoint.scheduleTrigger.schedule, "every 24 hours");
      assert.deepEqual(reconcileVoidedBoostPurchases.__endpoint.region, ["europe-west1"]);
    });
  });
});
