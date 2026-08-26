const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {BoostActivationService} = require("../lib/boost/boostActivationService.js");
const {DEFAULT_BOOST_PACKS, isDurationPack, defaultPackFor} = require("../lib/boost/catalog.js");

describe("boost duration packs", () => {
  it("exposes 7 / 30 / 365 day storefront SKUs", () => {
    const week = defaultPackFor("mevora_boost_7_days");
    const month = defaultPackFor("mevora_boost_1_month");
    const year = defaultPackFor("mevora_boost_1_year");
    assert.equal(week.durationDays, 7);
    assert.equal(month.durationDays, 30);
    assert.equal(year.durationDays, 365);
    assert.equal(isDurationPack(week), true);
    assert.equal(
      DEFAULT_BOOST_PACKS.filter((pack) => pack.storefront).map((pack) => pack.productId).join(","),
      "mevora_boost_7_days,mevora_boost_1_month,mevora_boost_1_year",
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
