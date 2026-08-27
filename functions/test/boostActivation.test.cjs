const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {BoostActivationService} = require("../lib/boost/boostActivationService.js");
const {DEFAULT_BOOST_PACKS, isDurationPack, defaultPackFor} = require("../lib/boost/catalog.js");

describe("boost duration packs", () => {
  it("exposes Smart Boost storefront SKUs (30m / 1h / 24h)", () => {
    const starter = defaultPackFor("mevora_smart_boost_30m");
    const popular = defaultPackFor("mevora_smart_boost_1h");
    const power = defaultPackFor("mevora_smart_boost_24h");
    assert.equal(starter.durationMs, 30 * 60 * 1000);
    assert.equal(popular.durationMs, 60 * 60 * 1000);
    assert.equal(power.durationMs, 24 * 60 * 60 * 1000);
    assert.equal(isDurationPack(starter), true);
    assert.equal(isDurationPack(popular), true);
    assert.equal(isDurationPack(power), true);
    assert.equal(
      DEFAULT_BOOST_PACKS.filter((pack) => pack.storefront).map((pack) => pack.productId).join(","),
      "mevora_smart_boost_30m,mevora_smart_boost_1h,mevora_smart_boost_24h",
    );
  });

  it("stacks remaining time onto a new grant", () => {
    const service = new BoostActivationService(true, 7 * 24 * 60 * 60 * 1000);
    const now = new Date("2026-08-18T12:00:00.000Z");
    const remaining = new Date(now.getTime() + 5 * 24 * 60 * 60 * 1000);
    const plan = service.decide({
      now,
      currentActive: {
        boostId: "b1",
        userId: "u1",
        status: "active",
        startedAt: now,
        expiresAt: remaining,
      },
      durationMs: 7 * 24 * 60 * 60 * 1000,
    });
    assert.equal(plan.shouldActivate, true);
    assert.equal(plan.extendBoostId, "b1");
    assert.equal(plan.expiresAt.getTime(), remaining.getTime() + 7 * 24 * 60 * 60 * 1000);
  });
});
