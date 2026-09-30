const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {createAdminWorld, rejectsWith, key} = require("./helpers/adminHarness.cjs");
const specs = require("../lib/admin/commands.js");
const {applyIdentityProviderEvent} = require("../lib/identity/identityVerificationStore.js");

async function world({status = "verified"} = {}) {
  const w = createAdminWorld();
  await w.addStaff("mod-1", "moderator");
  await w.addStaff("senior-1", "senior_moderator");
  await w.addMember("member-1", {account: {isVerified: status === "verified"}, profile: {isVerified: status === "verified"}});
  await w.db.doc("users/member-1/verification/identity").set({
    schemaVersion: 1,
    provider: "didit",
    providerSessionId: "sess-old-123456",
    status,
    attemptCount: 1,
    lastEventId: "evt-1",
    lastEventAtMs: w.now - 10_000,
    createdAt: new Date(w.now - 20_000),
    updatedAt: new Date(w.now - 10_000),
    verifiedAt: new Date(w.now - 10_000),
  });
  return w;
}

describe("verification — admins can inspect, escalate and revoke, never grant", () => {
  it("shows only the metadata MEVORA already stores", async () => {
    const w = await world();
    const v = await w.run(specs.adminGetVerificationSpec, "mod-1", {uid: "member-1"});
    assert.equal(v.identity.status, "verified");
    assert.equal(v.identity.provider, "didit");
    assert.equal(v.identity.providerSessionRef, "…123456", "session id is shortened");
    const json = JSON.stringify(v);
    for (const forbidden of ["document", "selfie", "liveness", "mrz", "biometric", "payload", "sess-old-123456"]) {
      assert.equal(json.toLowerCase().includes(forbidden), false, forbidden);
    }
  });

  it("there is no command, anywhere, that can set a member verified", () => {
    const names = Object.values(specs).map((s) => s.name.toLowerCase());
    for (const name of names) {
      assert.doesNotMatch(name, /markverified|forceverif|overrideverif|setverified|verifyuser/);
    }
    // Static guarantee: admin code never writes isVerified: true or status "verified".
    const adminDir = path.join(__dirname, "..", "src", "admin");
    const walk = (dir) => fs.readdirSync(dir, {withFileTypes: true}).flatMap((e) =>
      e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]);
    for (const file of walk(adminDir)) {
      const src = fs.readFileSync(file, "utf8");
      assert.doesNotMatch(src, /isVerified:\s*true/, file);
      assert.doesNotMatch(src, /status:\s*"verified"/, file);
    }
  });

  it("moderators cannot require re-verification; seniors can", async () => {
    const w = await world();
    const body = {uid: "member-1", reasonCode: "IMPERSONATION", internalNote: "photo mismatch reported", idempotencyKey: key()};
    await rejectsWith(w.run(specs.adminRequireReverificationSpec, "mod-1", body), "permission_denied");
    const result = await w.run(specs.adminRequireReverificationSpec, "senior-1", body);
    assert.equal(result.previousStatus, "verified");
  });

  it("require re-verification clears the badge everywhere and expires the state", async () => {
    const w = await world();
    const result = await w.run(specs.adminRequireReverificationSpec, "senior-1", {uid: "member-1", reasonCode: "IMPERSONATION", internalNote: "x", idempotencyKey: key()});
    const doc = w.db.read("users/member-1/verification/identity");
    assert.equal(doc.status, "expired");
    assert.equal(doc.reverificationRequired, true);
    assert.deepEqual(doc.revokedProviderSessionIds, ["sess-old-123456"]);
    assert.equal(w.db.read("users/member-1").isVerified, false);
    assert.equal(w.db.read("profiles/member-1").isVerified, false);
    const action = w.db.read(`moderationActions/${result.actionId}`);
    assert.equal(action.type, "REQUIRE_REVERIFICATION");
    assert.ok(w.db.paths().some((p) => p.startsWith("adminAuditLog/") && w.db.read(p).action === "VERIFICATION_REVERIFICATION_REQUIRED"));
  });

  it("a late or replayed webhook from the revoked session cannot restore the badge", async () => {
    const w = await world();
    await w.run(specs.adminRequireReverificationSpec, "senior-1", {uid: "member-1", reasonCode: "IMPERSONATION", internalNote: "x", idempotencyKey: key()});
    const late = await applyIdentityProviderEvent(w.db, {
      uid: "member-1",
      providerSessionId: "sess-old-123456",
      status: "verified",
      eventId: "evt-late",
      occurredAtMs: w.now + 60_000,
    }, "didit");
    assert.deepEqual(late, {applied: false, skipped: "session_revoked"});
    assert.equal(w.db.read("users/member-1").isVerified, false);
  });

  it("the provider remains the authority: a new verified session sets the badge again", async () => {
    const w = await world();
    await w.run(specs.adminRequireReverificationSpec, "senior-1", {uid: "member-1", reasonCode: "IMPERSONATION", internalNote: "x", idempotencyKey: key()});
    await w.db.doc("users/member-1/verification/identity").set({providerSessionId: "sess-new-999999", status: "pending"}, {merge: true});
    const fresh = await applyIdentityProviderEvent(w.db, {
      uid: "member-1",
      providerSessionId: "sess-new-999999",
      status: "verified",
      eventId: "evt-new",
      occurredAtMs: w.now + 120_000,
    }, "didit");
    assert.equal(fresh.applied, true);
    assert.equal(w.db.read("users/member-1").isVerified, true);
    assert.equal(w.db.read("users/member-1/verification/identity").reverificationRequired, false);
  });

  it("re-verification is idempotent per submission", async () => {
    const w = await world();
    const k = key();
    const a = await w.run(specs.adminRequireReverificationSpec, "senior-1", {uid: "member-1", reasonCode: "OTHER", internalNote: "x", idempotencyKey: k});
    const b = await w.run(specs.adminRequireReverificationSpec, "senior-1", {uid: "member-1", reasonCode: "OTHER", internalNote: "x", idempotencyKey: k});
    assert.equal(b.replayed, true);
    assert.equal(a.actionId, b.actionId);
  });

  it("escalation opens a VERIFICATION_REVIEW case", async () => {
    const w = await world({status: "in_review"});
    const result = await w.run(specs.adminEscalateVerificationSpec, "mod-1", {uid: "member-1", reason: "document looks altered"});
    assert.equal(w.db.read(`moderationCases/${result.caseId}`).type, "VERIFICATION_REVIEW");
  });

  it("the review queue lists verification documents by status", async () => {
    const w = await world({status: "in_review"});
    const queue = await w.run(specs.adminListVerificationReviewsSpec, "mod-1", {filter: "in_review"});
    assert.equal(queue.items.length, 1);
    assert.equal(queue.items[0].uid, "member-1");
  });
});
