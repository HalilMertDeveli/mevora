const {describe, it} = require("node:test");
const assert = require("node:assert/strict");

// The set reportUser validates against, not a copy of it.
const {REPORT_REASONS} = require("../lib/admin/reports/reportPriority.js");

describe("report compliance", () => {
  it("accepts the production report reason whitelist", () => {
    for (const reason of [
      "spam",
      "harassment",
      "inappropriate_content",
      "scam",
      "fake_profile",
      "underage",
      "child_safety",
      "other",
    ]) {
      assert.equal(REPORT_REASONS.has(reason), true);
    }
  });

  it("rejects unknown report reasons", () => {
    assert.equal(REPORT_REASONS.has("guaranteed_match"), false);
    assert.equal(REPORT_REASONS.has(""), false);
    assert.equal(REPORT_REASONS.has("admin_override"), false);
  });
});
