const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {evaluatePremiumAccess} = require("../lib/subscription/entitlementPolicy.js");
const {
  SubscriptionEntitlementWriter,
  decideWrite,
  defaultEntitlementFor,
  mergeEntitlement,
} = require("../lib/subscription/entitlementWriter.js");
const {
  fromDocument,
  subscriptionDocPath,
} = require("../lib/subscription/firestoreEntitlementStore.js");

const NOW = new Date("2026-09-22T12:00:00.000Z");
const FUTURE = new Date("2026-10-22T12:00:00.000Z");
const PAST = new Date("2026-08-22T12:00:00.000Z");

function state(overrides) {
  return {
    userId: "u1",
    platform: "android",
    productId: "mevora_premium_monthly",
    status: "active",
    entitlement: "premium",
    originalTransactionId: "oti-1",
    latestPurchaseId: "p-1",
    expiresAt: FUTURE,
    graceUntil: null,
    autoRenewing: true,
    lastVerifiedAt: NOW,
    storeEnvironment: "production",
    source: "store",
    revision: 1,
    eventAt: NOW,
    isPremium: true,
    ...overrides,
  };
}

function memoryPersistence(initial = null) {
  const store = {
    current: initial,
    writes: 0,
    async transact(userId, mutate) {
      const next = mutate(store.current);
      if (next !== null) {
        store.current = next;
        store.writes += 1;
      }
      return store.current;
    },
  };
  return store;
}

describe("premium entitlement policy", () => {
  it("active subscription grants premium", () => {
    const access = evaluatePremiumAccess(state(), NOW);
    assert.equal(access.isPremium, true);
    assert.equal(access.reason, "active");
    assert.deepEqual(access.accessUntil, FUTURE);
  });

  it("expired subscription does not grant premium", () => {
    const access = evaluatePremiumAccess(
      state({status: "expired", entitlement: "none", expiresAt: PAST}),
      NOW,
    );
    assert.equal(access.isPremium, false);
    assert.equal(access.reason, "expired");
  });

  it("active subscription past its expiry does not grant premium", () => {
    const access = evaluatePremiumAccess(state({expiresAt: PAST}), NOW);
    assert.equal(access.isPremium, false);
    assert.equal(access.reason, "expired");
  });

  it("cancelled subscription keeps access until the paid period ends", () => {
    const access = evaluatePremiumAccess(
      state({status: "cancelled", autoRenewing: false, expiresAt: FUTURE}),
      NOW,
    );
    assert.equal(access.isPremium, true);
    assert.equal(access.reason, "paid_period_remaining");
    assert.deepEqual(access.accessUntil, FUTURE);
  });

  it("cancelled and expired subscription does not grant premium", () => {
    const access = evaluatePremiumAccess(
      state({status: "cancelled", autoRenewing: false, expiresAt: PAST}),
      NOW,
    );
    assert.equal(access.isPremium, false);
    assert.equal(access.reason, "expired");
  });

  it("cancelled subscription without an expiry fails safe to free", () => {
    const access = evaluatePremiumAccess(
      state({status: "cancelled", expiresAt: null}),
      NOW,
    );
    assert.equal(access.isPremium, false);
    assert.equal(access.reason, "no_deadline");
  });

  it("grace period keeps access while the grace window is open", () => {
    const access = evaluatePremiumAccess(
      state({status: "grace_period", expiresAt: PAST, graceUntil: FUTURE}),
      NOW,
    );
    assert.equal(access.isPremium, true);
    assert.equal(access.reason, "grace");
    assert.deepEqual(access.accessUntil, FUTURE);
  });

  it("grace period that has run out does not grant premium", () => {
    const access = evaluatePremiumAccess(
      state({status: "grace_period", expiresAt: PAST, graceUntil: PAST}),
      NOW,
    );
    assert.equal(access.isPremium, false);
    assert.equal(access.reason, "expired");
  });

  it("billing retry without a store grace window does not grant premium", () => {
    const access = evaluatePremiumAccess(
      state({status: "billing_retry", expiresAt: PAST, graceUntil: null}),
      NOW,
    );
    assert.equal(access.isPremium, false);
    assert.equal(access.reason, "expired");
  });

  it("billing retry inside a store grace window keeps access", () => {
    const access = evaluatePremiumAccess(
      state({status: "billing_retry", expiresAt: PAST, graceUntil: FUTURE}),
      NOW,
    );
    assert.equal(access.isPremium, true);
    assert.equal(access.reason, "grace");
  });

  it("refunded revokes access even when the paid period is unfinished", () => {
    const access = evaluatePremiumAccess(
      state({status: "refunded", expiresAt: FUTURE}),
      NOW,
    );
    assert.equal(access.isPremium, false);
    assert.equal(access.reason, "refunded");
  });

  it("revoked removes access even when the paid period is unfinished", () => {
    const access = evaluatePremiumAccess(
      state({status: "revoked", expiresAt: FUTURE}),
      NOW,
    );
    assert.equal(access.isPremium, false);
    assert.equal(access.reason, "revoked");
  });

  it("entitlement none never grants premium", () => {
    const access = evaluatePremiumAccess(
      state({entitlement: "none", expiresAt: FUTURE}),
      NOW,
    );
    assert.equal(access.isPremium, false);
    assert.equal(access.reason, "entitlement_none");
  });

  it("missing or unknown state fails safe to free", () => {
    assert.equal(evaluatePremiumAccess(null, NOW).isPremium, false);
    assert.equal(evaluatePremiumAccess(undefined, NOW).reason, "no_subscription");
    // Deliberately a status no store will ever send. "paused" used to stand in
    // here; it is a real canonical state now, so the guard needs a fresh one.
    const unknown = evaluatePremiumAccess(
      state({status: "some_future_store_state"}),
      NOW,
    );
    assert.equal(unknown.isPremium, false);
    assert.equal(unknown.reason, "invalid_state");
  });

  it("paused never grants premium", () => {
    const access = evaluatePremiumAccess(state({status: "paused"}), NOW);
    assert.equal(access.isPremium, false);
    assert.equal(access.reason, "paused");
    assert.equal(access.accessUntil, null);
  });

  it("paused with a future expiry still grants nothing", () => {
    const access = evaluatePremiumAccess(
      state({status: "paused", expiresAt: FUTURE}),
      NOW,
    );
    assert.equal(access.isPremium, false);
    assert.equal(access.reason, "paused");
  });

  it("paused with a future grace window still grants nothing", () => {
    const access = evaluatePremiumAccess(
      state({status: "paused", expiresAt: FUTURE, graceUntil: FUTURE}),
      NOW,
    );
    assert.equal(access.isPremium, false);
    assert.equal(access.reason, "paused");
  });

  it("pending never grants premium", () => {
    const access = evaluatePremiumAccess(state({status: "pending"}), NOW);
    assert.equal(access.isPremium, false);
    assert.equal(access.reason, "pending");
    assert.equal(access.accessUntil, null);
  });

  it("pending with a future expiry still grants nothing", () => {
    const access = evaluatePremiumAccess(
      state({status: "pending", expiresAt: FUTURE}),
      NOW,
    );
    assert.equal(access.isPremium, false);
    assert.equal(access.reason, "pending");
  });

  it("a legacy isPremium mirror cannot override paused or pending", () => {
    for (const status of ["paused", "pending"]) {
      const canonical = fromDocument("u1", {
        status,
        entitlement: "premium",
        isPremium: true,
        expiresAt: FUTURE,
      });
      assert.equal(canonical.status, status, `${status} must survive the mapper`);
      const access = evaluatePremiumAccess(canonical, NOW);
      assert.equal(access.isPremium, false, `${status} must not grant premium`);
      assert.equal(access.reason, status);
    }
  });

  it("paused and pending are not stored as expired", () => {
    for (const status of ["paused", "pending"]) {
      const canonical = fromDocument("u1", {status, entitlement: "none"});
      assert.equal(canonical.status, status);
      assert.notEqual(canonical.status, "expired");
      assert.equal(canonical.source, "store", "must not be read as a legacy doc");
    }
  });

  it("active grant without an expiry stays premium (manual/lifetime)", () => {
    const access = evaluatePremiumAccess(
      state({expiresAt: null, source: "manual", autoRenewing: false}),
      NOW,
    );
    assert.equal(access.isPremium, true);
    assert.equal(access.reason, "active");
    assert.equal(access.accessUntil, null);
  });
});

describe("entitlement merge", () => {
  it("derives the grant from the status when the caller omits it", () => {
    assert.equal(defaultEntitlementFor("active"), "premium");
    assert.equal(defaultEntitlementFor("cancelled"), "premium");
    assert.equal(defaultEntitlementFor("grace_period"), "premium");
    assert.equal(defaultEntitlementFor("billing_retry"), "premium");
    assert.equal(defaultEntitlementFor("expired"), "none");
    assert.equal(defaultEntitlementFor("paused"), "none");
    assert.equal(defaultEntitlementFor("pending"), "none");
    assert.equal(defaultEntitlementFor("revoked"), "none");
    assert.equal(defaultEntitlementFor("refunded"), "none");
  });

  it("writing a pause clears the derived premium mirror", () => {
    const merged = mergeEntitlement(
      state(),
      {userId: "u1", status: "paused"},
      NOW,
    );
    assert.equal(merged.status, "paused");
    assert.equal(merged.entitlement, "none");
    assert.equal(merged.isPremium, false);
    // The paid-period deadline is still on record; it just grants nothing.
    assert.deepEqual(merged.expiresAt, FUTURE);
  });

  it("keeps existing identifiers the caller did not supply", () => {
    const merged = mergeEntitlement(
      state(),
      {userId: "u1", status: "cancelled", autoRenewing: false},
      NOW,
    );
    assert.equal(merged.originalTransactionId, "oti-1");
    assert.equal(merged.productId, "mevora_premium_monthly");
    assert.equal(merged.platform, "android");
    assert.equal(merged.status, "cancelled");
    assert.equal(merged.autoRenewing, false);
  });

  it("always rewrites the derived isPremium mirror", () => {
    const merged = mergeEntitlement(
      state(),
      {userId: "u1", status: "refunded", expiresAt: FUTURE},
      NOW,
    );
    assert.equal(merged.entitlement, "none");
    assert.equal(merged.isPremium, false);
  });
});

describe("entitlement write ordering", () => {
  it("applies the first event for a user", () => {
    const decision = decideWrite(
      null,
      {userId: "u1", status: "active", expiresAt: FUTURE},
      NOW,
    );
    assert.equal(decision.outcome, "applied");
    assert.equal(decision.state.isPremium, true);
  });

  it("rejects an event with an older revision", () => {
    const decision = decideWrite(
      state({revision: 5}),
      {userId: "u1", status: "expired", revision: 4},
      NOW,
    );
    assert.equal(decision.outcome, "stale_revision");
    assert.equal(decision.state.status, "active");
  });

  it("rejects an event that is older by event time", () => {
    const decision = decideWrite(
      state({eventAt: NOW, revision: 0}),
      {userId: "u1", status: "expired", eventAt: PAST},
      NOW,
    );
    assert.equal(decision.outcome, "stale_event");
    assert.equal(decision.state.status, "active");
  });

  it("accepts a newer revision", () => {
    const decision = decideWrite(
      state({revision: 5}),
      {userId: "u1", status: "cancelled", revision: 6, autoRenewing: false},
      NOW,
    );
    assert.equal(decision.outcome, "applied");
    assert.equal(decision.state.status, "cancelled");
  });

  it("does not let an unordered event resurrect a refunded subscription", () => {
    const decision = decideWrite(
      state({status: "refunded", entitlement: "none", revision: 0, eventAt: null}),
      {userId: "u1", status: "active", expiresAt: FUTURE},
      NOW,
    );
    assert.equal(decision.outcome, "terminal_state");
    assert.equal(decision.state.status, "refunded");
  });

  it("lets a provably newer event move a refunded subscription", () => {
    const decision = decideWrite(
      state({status: "refunded", entitlement: "none", revision: 3}),
      {userId: "u1", status: "active", expiresAt: FUTURE, revision: 4},
      NOW,
    );
    assert.equal(decision.outcome, "applied");
    assert.equal(decision.state.status, "active");
  });
});

describe("entitlement writer", () => {
  it("is idempotent when the same event is delivered twice", async () => {
    const persistence = memoryPersistence();
    const writer = new SubscriptionEntitlementWriter(persistence, () => NOW);
    const event = {
      userId: "u1",
      status: "active",
      platform: "android",
      productId: "mevora_premium_monthly",
      expiresAt: FUTURE,
      autoRenewing: true,
      revision: 7,
      eventAt: NOW,
      storeEnvironment: "production",
    };

    const first = await writer.apply(event);
    assert.equal(first.outcome, "applied");
    assert.equal(first.applied, true);
    assert.equal(persistence.writes, 1);

    const second = await writer.apply(event);
    assert.equal(second.outcome, "noop");
    assert.equal(second.applied, false);
    assert.equal(persistence.writes, 1);
    assert.equal(second.state.isPremium, true);
  });

  it("does not write when a stale event arrives", async () => {
    const persistence = memoryPersistence(state({revision: 9}));
    const writer = new SubscriptionEntitlementWriter(persistence, () => NOW);
    const result = await writer.apply({userId: "u1", status: "expired", revision: 2});
    assert.equal(result.outcome, "stale_revision");
    assert.equal(persistence.writes, 0);
    assert.equal(persistence.current.status, "active");
  });

  it("writes the full lifecycle through one reusable path", async () => {
    const persistence = memoryPersistence();
    const writer = new SubscriptionEntitlementWriter(persistence, () => NOW);

    const bought = await writer.apply({
      userId: "u1",
      status: "active",
      platform: "ios",
      productId: "premium_monthly",
      expiresAt: FUTURE,
      autoRenewing: true,
      revision: 1,
    });
    assert.equal(bought.state.isPremium, true);

    const cancelled = await writer.apply({
      userId: "u1",
      status: "cancelled",
      autoRenewing: false,
      revision: 2,
    });
    assert.equal(cancelled.state.isPremium, true, "paid period survives cancellation");

    const refunded = await writer.apply({userId: "u1", status: "refunded", revision: 3});
    assert.equal(refunded.state.isPremium, false);
    assert.equal(refunded.state.entitlement, "none");
  });

  it("refuses a write without a user id", async () => {
    const writer = new SubscriptionEntitlementWriter(memoryPersistence(), () => NOW);
    await assert.rejects(() => writer.apply({userId: "", status: "active"}));
  });
});

describe("legacy document compatibility", () => {
  it("reads a pre-P0 premium document as an active subscription", () => {
    const canonical = fromDocument("u1", {isPremium: true, expiresAt: null});
    assert.equal(canonical.status, "active");
    assert.equal(canonical.entitlement, "premium");
    assert.equal(canonical.source, "legacy_claim");
    assert.equal(evaluatePremiumAccess(canonical, NOW).isPremium, true);
  });

  it("reads a pre-P0 non-premium document as expired", () => {
    const canonical = fromDocument("u1", {isPremium: false});
    assert.equal(canonical.status, "expired");
    assert.equal(evaluatePremiumAccess(canonical, NOW).isPremium, false);
  });

  it("treats an unknown status as legacy rather than trusting it", () => {
    const canonical = fromDocument("u1", {status: "nonsense", isPremium: true});
    assert.equal(canonical.status, "active");
    assert.equal(canonical.entitlement, "premium");
  });

  it("returns null when there is no document", () => {
    assert.equal(fromDocument("u1", undefined), null);
  });

  it("keeps the canonical document path unchanged", () => {
    assert.equal(subscriptionDocPath("u1"), "users/u1/subscription/current");
  });
});

describe("server-only entitlement surface", () => {
  const src = (name) =>
    fs.readFileSync(path.join(__dirname, "..", "src", name), "utf8");

  // P0 asserted this module exposed no callable at all, because nothing but
  // server code wrote entitlement. Each entry point added since had to earn a
  // line here rather than the guard being loosened: the callable, because a
  // client cannot present store evidence without one, and the Pub/Sub trigger,
  // because Play's own notifications have nowhere else to arrive.
  //
  // Both are held to the same rule — go and ask the store, then write what the
  // store said. Neither may read entitlement off the thing that woke it up.
  const SUBSCRIPTION_ENTRY_POINTS = {
    "verifyPremiumPurchase.ts": ["onCall("],
    "googleRtdnFunction.ts": ["onMessagePublished("],
  };

  it("exposes only the allowlisted entitlement entry points", () => {
    const dir = path.join(__dirname, "..", "src", "subscription");
    for (const file of fs.readdirSync(dir)) {
      const code = fs.readFileSync(path.join(dir, file), "utf8");
      const allowed = SUBSCRIPTION_ENTRY_POINTS[file] ?? [];
      for (const surface of ["onCall(", "onRequest(", "onMessagePublished("]) {
        if (allowed.includes(surface)) {
          continue;
        }
        assert.equal(
          code.includes(surface),
          false,
          file + " exposes an unreviewed " + surface + " surface",
        );
      }
    }
  });

  it("the purchase entry point verifies with the store before it writes", () => {
    const code = src("subscription/verifyPremiumPurchase.ts");
    const verifyAt = code.indexOf("fetchSubscription");
    const writeAt = code.indexOf("writer.apply");
    assert.ok(verifyAt > 0, "must call the store verifier");
    assert.ok(writeAt > 0, "must reach the entitlement writer");
    assert.ok(
      verifyAt < writeAt,
      "store verification must happen before the entitlement write",
    );
  });

  it("the notification handler verifies with the store before it writes", () => {
    const code = src("subscription/googleRtdn.ts");
    const verifyAt = code.indexOf("fetchSubscription");
    const writeAt = code.indexOf("writer.apply");
    assert.ok(verifyAt > 0, "must call the store verifier");
    assert.ok(writeAt > 0, "must reach the entitlement writer");
    assert.ok(
      verifyAt < writeAt,
      "store verification must happen before the entitlement write",
    );
  });

  it("the notification handler takes no state from the notification itself", () => {
    const code = src("subscription/googleRtdn.ts");
    // Play's notificationType names what supposedly happened — RENEWED,
    // CANCELED, REVOKED. Branching entitlement on it would write a story
    // instead of a fact, and at-least-once delivery means the story can be
    // stale, duplicated or superseded. The type is read only to find the
    // token; the state comes from subscriptionsv2.get.
    const typeAt = code.indexOf("notificationType");
    assert.ok(typeAt > 0, "the notification shape still declares the type");
    for (const branch of [
      "notificationType ===",
      "notificationType ==",
      "switch (notification.subscriptionNotification?.notificationType",
    ]) {
      assert.equal(
        code.includes(branch),
        false,
        "must not decide entitlement from " + branch,
      );
    }
  });

  it("the purchase entry point takes no entitlement claim from the client", () => {
    const code = src("subscription/verifyPremiumPurchase.ts");
    // The request may name a token and a platform. Anything that would let the
    // caller assert what it bought, how long for, or that it is premium must
    // never be read off the request.
    for (const claimed of [
      "data.isPremium",
      "data.premium",
      "data.entitlement",
      "data.status",
      "data.expiresAt",
      "data.productId",
    ]) {
      assert.equal(
        code.includes(claimed),
        false,
        "must not read " + claimed + " from the client",
      );
    }
  });

  it("index.ts exports the two entitlement entry points and nothing else", () => {
    // The subscription module is mostly internal: writer, policy, mapper,
    // catalogue, ownership. Exactly two things are reachable from outside —
    // the client's purchase verification, and Google's notification topic.
    // Anything else appearing here would be a new way into entitlement.
    const index = src("index.ts");
    const marker = "./subscription/";
    const exported = index
      .split(/\r?\n/)
      .filter((line) => line.includes(marker))
      .map((line) => line.slice(line.indexOf(marker) + marker.length))
      .map((rest) => rest.slice(0, rest.indexOf('"')));
    assert.deepEqual(exported.slice().sort(), [
      "googleRtdnFunction.js",
      "verifyPremiumPurchase.js",
    ]);
  });

  it("account deletion releases the purchase tokens that account owned", () => {
    // Deleting a Mevora account does not cancel the store subscription, so the
    // person may still be paying for it. If the ownership claim outlived the
    // account, their next account could not restore what they bought — the
    // ledger would report the token as owned by a uid that no longer exists —
    // and RTDN would keep writing entitlement documents for a deleted user.
    const code = src("deleteAccount.ts");
    assert.ok(
      code.includes('deleteQuery("subscriptionPurchases", "userId", uid)'),
      "deletion must release this account's purchase ownership records",
    );
    assert.ok(
      code.includes('deleteCollectionDocs(`users/${uid}/subscription`)'),
      "deletion must still remove the entitlement document itself",
    );
  });

  it("resolves premium through the canonical model only", () => {
    const premium = src("premium.ts");
    assert.equal(premium.includes("resolvePremiumAccess"), true);
    assert.equal(
      premium.includes("customClaims"),
      false,
      "claim handling belongs to the canonical resolver",
    );
    const resolver = src("subscription/entitlementResolver.ts");
    assert.equal(resolver.includes("readCanonicalSubscription"), true);
    assert.equal(resolver.includes("customClaims"), true);
  });

  it("keeps existing premium consumers on the shared resolver", () => {
    for (const consumer of ["incomingLikes.ts", "spotifyMusic.ts"]) {
      assert.equal(
        src(consumer).includes("isUserPremium"),
        true,
        consumer + " must keep using the shared resolver",
      );
    }
  });
});
