const test = require("node:test");
const assert = require("node:assert/strict");
const {
  isPremiumProduct,
  resolvePremiumPack,
  PREMIUM_PRODUCT_IDS,
} = require("../lib/premium/catalog.js");

test("premium catalog resolves month and year packs", () => {
  assert.equal(isPremiumProduct(PREMIUM_PRODUCT_IDS.month), true);
  assert.equal(isPremiumProduct("mevora_boost_7_days"), false);
  const month = resolvePremiumPack(PREMIUM_PRODUCT_IDS.month);
  assert.ok(month);
  assert.equal(month.durationDays, 30);
  const year = resolvePremiumPack(PREMIUM_PRODUCT_IDS.year);
  assert.ok(year);
  assert.equal(year.durationDays, 365);
});
