const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  mapSumsubToVerificationStatus,
  shouldSetVerified,
  isTerminalStatus,
} = require("../lib/sumsub/sumsubStatus.js");

describe("sumsub status mapping", () => {
  it("maps GREEN applicantReviewed to approved", () => {
    const status = mapSumsubToVerificationStatus({
      type: "applicantReviewed",
      reviewStatus: "completed",
      reviewResult: {reviewAnswer: "GREEN"},
    });
    assert.equal(status, "approved");
    assert.equal(shouldSetVerified(status), true);
    assert.equal(isTerminalStatus(status), true);
  });

  it("maps RED retry reject to retry_required", () => {
    const status = mapSumsubToVerificationStatus({
      type: "applicantReviewed",
      reviewStatus: "completed",
      reviewResult: {reviewAnswer: "RED", reviewRejectType: "RETRY"},
    });
    assert.equal(status, "retry_required");
    assert.equal(shouldSetVerified(status), false);
  });

  it("maps RED final reject to rejected", () => {
    const status = mapSumsubToVerificationStatus({
      type: "applicantReviewed",
      reviewStatus: "completed",
      reviewResult: {reviewAnswer: "RED", reviewRejectType: "FINAL"},
    });
    assert.equal(status, "rejected");
    assert.equal(isTerminalStatus(status), true);
  });

  it("maps pending webhook types to pending", () => {
    assert.equal(
      mapSumsubToVerificationStatus({type: "applicantPending", reviewStatus: "pending"}),
      "pending",
    );
    assert.equal(
      mapSumsubToVerificationStatus({type: "applicantOnHold", reviewStatus: "onHold"}),
      "pending",
    );
  });

  it("maps applicantCreated to started", () => {
    assert.equal(
      mapSumsubToVerificationStatus({type: "applicantCreated"}),
      "started",
    );
  });
});
