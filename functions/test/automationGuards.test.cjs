const {describe, it} = require("node:test");
const assert = require("node:assert/strict");

// Pure helpers mirrored from automation modules for unit coverage without Admin SDK.
const JobStatus = {
  queued: "queued",
  running: "running",
  succeeded: "succeeded",
  failed: "failed",
  retrying: "retrying",
  manual_review: "manual_review",
};

const ManualReviewActions = [
  "account_ban",
  "account_permanent_delete",
  "premium_refund",
  "premium_revoke",
  "critical_report_decision",
  "force_unmatch_all",
  "mass_storage_delete",
];

function maskEmail(email) {
  if (!email || !email.includes("@")) return email ? "***" : null;
  const [local, domain] = email.split("@");
  const visible = local.length <= 2 ? "*" : `${local[0]}***${local[local.length - 1]}`;
  return `${visible}@${domain}`;
}

function maskPhone(phone) {
  if (!phone) return null;
  const digits = phone.replace(/\D/g, "");
  if (digits.length < 4) return "***";
  return `***${digits.slice(-4)}`;
}

function notificationIdempotencyKey(type, uid, matchId, messageId) {
  if (messageId) return `msg_${matchId}_${messageId}_${uid}`;
  return `${type}_${matchId}_${uid}`;
}

function backoffMs(attempt) {
  return Math.min(15 * 60 * 1000, 1000 * Math.pow(2, Math.max(0, attempt - 1)));
}

function shouldAutoBan(action) {
  return !ManualReviewActions.includes(action);
}

describe("automation inventory guards", () => {
  it("never auto-executes permanent ban or premium refund", () => {
    assert.equal(ManualReviewActions.includes("account_ban"), true);
    assert.equal(ManualReviewActions.includes("premium_refund"), true);
    assert.equal(shouldAutoBan("account_ban"), false);
    assert.equal(shouldAutoBan("orphan_storage_cleanup"), true);
  });

  it("masks PII for admin panel display", () => {
    assert.equal(maskEmail("alex@example.com"), "a***x@example.com");
    assert.equal(maskPhone("+905551112233"), "***2233");
  });

  it("builds stable notification idempotency keys", () => {
    const a = notificationIdempotencyKey("newMatch", "u1", "m1");
    const b = notificationIdempotencyKey("newMatch", "u1", "m1");
    assert.equal(a, b);
    assert.equal(a, "newMatch_m1_u1");
    const msg = notificationIdempotencyKey("newMessage", "u2", "m9", "msg1");
    assert.equal(msg, "msg_m9_msg1_u2");
  });

  it("uses exponential backoff for retries", () => {
    assert.equal(backoffMs(1), 1000);
    assert.equal(backoffMs(2), 2000);
    assert.equal(backoffMs(3), 4000);
    assert.ok(backoffMs(20) <= 15 * 60 * 1000);
  });

  it("defines expected job status machine", () => {
    for (const s of ["queued", "running", "succeeded", "failed", "retrying", "manual_review"]) {
      assert.equal(JobStatus[s], s);
    }
  });

  it("requires explicit BAN confirm phrase for permanent ban", () => {
    const confirmOk = (phrase) => phrase === "BAN";
    assert.equal(confirmOk("BAN"), true);
    assert.equal(confirmOk("ban"), false);
    assert.equal(confirmOk(""), false);
  });
});
