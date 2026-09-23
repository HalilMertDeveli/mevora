const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  IDENTITY_VERIFICATION_STATUSES,
  canStartIdentityVerification,
  grantsVerifiedBadge,
  identityVerificationDocPath,
  isTerminalIdentityStatus,
  parseIdentityVerificationStatus,
  mapDiditStatus,
  correlationUidFromWebhook,
  mapLegacySumsubStatus,
} = require("../lib/identity/index.js");

describe("provider-neutral identity verification status", () => {
  it("covers every status the migration design names", () => {
    assert.deepEqual([...IDENTITY_VERIFICATION_STATUSES], [
      "not_started",
      "pending",
      "in_progress",
      "in_review",
      "verified",
      "declined",
      "expired",
      "error",
    ]);
  });

  it("grants the verified badge for exactly one status", () => {
    const granting = IDENTITY_VERIFICATION_STATUSES.filter(grantsVerifiedBadge);
    assert.deepEqual(granting, ["verified"]);
  });

  it("treats verified, declined and expired as terminal", () => {
    const terminal = IDENTITY_VERIFICATION_STATUSES.filter(isTerminalIdentityStatus);
    assert.deepEqual(terminal, ["verified", "declined", "expired"]);
  });

  it("never lets an already-verified or in-flight user start again", () => {
    assert.equal(canStartIdentityVerification("not_started"), true);
    assert.equal(canStartIdentityVerification("declined"), true);
    assert.equal(canStartIdentityVerification("expired"), true);
    assert.equal(canStartIdentityVerification("error"), true);
    assert.equal(canStartIdentityVerification("pending"), false);
    assert.equal(canStartIdentityVerification("in_progress"), false);
    assert.equal(canStartIdentityVerification("in_review"), false);
    assert.equal(canStartIdentityVerification("verified"), false);
  });

  it("parses known statuses and degrades unknown ones to error", () => {
    for (const status of IDENTITY_VERIFICATION_STATUSES) {
      assert.equal(parseIdentityVerificationStatus(status), status);
    }
    assert.equal(parseIdentityVerificationStatus(undefined), "not_started");
    assert.equal(parseIdentityVerificationStatus(""), "not_started");
    assert.equal(parseIdentityVerificationStatus("approved"), "error");
    assert.equal(parseIdentityVerificationStatus(true), "error");
    assert.equal(parseIdentityVerificationStatus({status: "verified"}), "error");
  });

  it("names the verification document without naming a provider", () => {
    assert.equal(identityVerificationDocPath("uid-1"), "users/uid-1/verification/identity");
  });
});

describe("Didit status mapping", () => {
  it("maps every documented Didit status", () => {
    assert.equal(mapDiditStatus("Not Started"), "not_started");
    assert.equal(mapDiditStatus("In Progress"), "in_progress");
    assert.equal(mapDiditStatus("Awaiting User"), "pending");
    assert.equal(mapDiditStatus("Resubmitted"), "in_progress");
    assert.equal(mapDiditStatus("In Review"), "in_review");
    assert.equal(mapDiditStatus("Approved"), "verified");
    assert.equal(mapDiditStatus("Declined"), "declined");
    assert.equal(mapDiditStatus("Expired"), "expired");
    assert.equal(mapDiditStatus("Abandoned"), "expired");
    assert.equal(mapDiditStatus("Kyc Expired"), "expired");
  });

  it("approves on exactly one Didit status", () => {
    const all = [
      "Not Started", "In Progress", "Awaiting User", "In Review", "Resubmitted",
      "Approved", "Declined", "Expired", "Abandoned", "Kyc Expired",
    ];
    const approving = all.filter((s) => grantsVerifiedBadge(mapDiditStatus(s)));
    assert.deepEqual(approving, ["Approved"]);
  });

  it("refuses to guess at casing, spacing or unknown statuses", () => {
    assert.equal(mapDiditStatus("approved"), "error");
    assert.equal(mapDiditStatus("APPROVED"), "error");
    assert.equal(mapDiditStatus("in_review"), "error");
    assert.equal(mapDiditStatus("KYC Expired"), "error");
    assert.equal(mapDiditStatus("Something New"), "error");
    assert.equal(mapDiditStatus(undefined), "error");
    assert.equal(mapDiditStatus(null), "error");
    assert.equal(mapDiditStatus(1), "error");
  });

  it("cannot be tricked into granting the badge by a non-string payload", () => {
    for (const raw of [undefined, null, 1, true, {}, [], "Approved "]) {
      assert.equal(grantsVerifiedBadge(mapDiditStatus(raw)), false);
    }
  });

  it("correlates a webhook only through vendor_data", () => {
    assert.equal(correlationUidFromWebhook({vendor_data: "uid-1"}), "uid-1");
    assert.equal(correlationUidFromWebhook({vendor_data: "  uid-2  "}), "uid-2");
    assert.equal(correlationUidFromWebhook({}), null);
    assert.equal(correlationUidFromWebhook({vendor_data: ""}), null);
    assert.equal(correlationUidFromWebhook({vendor_data: "   "}), null);
    assert.equal(correlationUidFromWebhook({session_id: "s-1"}), null);
  });
});

describe("legacy Sumsub status bridge", () => {
  it("translates every legacy status into the neutral vocabulary", () => {
    assert.equal(mapLegacySumsubStatus("not_started"), "not_started");
    assert.equal(mapLegacySumsubStatus("started"), "in_progress");
    assert.equal(mapLegacySumsubStatus("pending"), "in_review");
    assert.equal(mapLegacySumsubStatus("approved"), "verified");
    assert.equal(mapLegacySumsubStatus("rejected"), "declined");
    assert.equal(mapLegacySumsubStatus("retry_required"), "expired");
  });

  it("approves on exactly one legacy status", () => {
    const all = ["not_started", "started", "pending", "approved", "rejected", "retry_required"];
    const approving = all.filter((s) => grantsVerifiedBadge(mapLegacySumsubStatus(s)));
    assert.deepEqual(approving, ["approved"]);
  });

  it("degrades unknown legacy values without granting anything", () => {
    assert.equal(mapLegacySumsubStatus("GREEN"), "error");
    assert.equal(mapLegacySumsubStatus(undefined), "not_started");
    assert.equal(grantsVerifiedBadge(mapLegacySumsubStatus("GREEN")), false);
    assert.equal(grantsVerifiedBadge(mapLegacySumsubStatus(undefined)), false);
  });
});
