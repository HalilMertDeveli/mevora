const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {createAdminWorld, rejectsWith, key} = require("./helpers/adminHarness.cjs");
const specs = require("../lib/admin/commands.js");
const {scrubAuditMetadata, appendAuditEvent} = require("../lib/admin/audit/auditService.js");

async function world() {
  const w = createAdminWorld();
  await w.addStaff("mod-1", "moderator");
  await w.addStaff("senior-1", "senior_moderator");
  await w.addStaff("tsa-1", "trust_safety_admin");
  await w.addMember("member-1", {account: {phoneNumber: "+905551112233"}});
  return w;
}

const events = (w) => w.db.paths().filter((p) => p.startsWith("adminAuditLog/")).map((p) => w.db.read(p));

describe("audit log", () => {
  it("every high-impact action produces an audit event naming actor, target and request", async () => {
    const w = await world();
    await w.run(specs.adminWarnUserSpec, "mod-1", {uid: "member-1", reasonCode: "SPAM", idempotencyKey: key()});
    await w.run(specs.adminSuspendUserSpec, "mod-1", {uid: "member-1", reasonCode: "SPAM", durationHours: 24, internalNote: "x", idempotencyKey: key()});
    await w.run(specs.adminBanUserSpec, "senior-1", {uid: "member-1", reasonCode: "SPAM", internalNote: "x", idempotencyKey: key()});
    await w.run(specs.adminRestoreUserSpec, "senior-1", {uid: "member-1", reasonCode: "ERROR_CORRECTION", internalNote: "x", idempotencyKey: key()});
    const actions = events(w).map((e) => e.action).sort();
    assert.deepEqual(actions, ["USER_BANNED", "USER_RESTORED", "USER_SUSPENDED", "USER_WARNED"]);
    for (const e of events(w)) {
      assert.equal(e.targetId, "member-1");
      assert.ok(e.actorAdminId);
      assert.ok(e.requestId);
      assert.ok(e.actionId);
    }
  });

  it("scrubs secrets, message bodies, identity data and free text from metadata", () => {
    const out = scrubAuditMetadata({
      reasonCode: "SPAM",
      password: "hunter2",
      idToken: "eyJ...",
      otp: "123456",
      authorization: "Bearer x",
      messageText: "hello",
      ciphertext: "AAAA",
      documentNumber: "U1234",
      selfieUrl: "https://x",
      rawPayload: {a: 1},
      internalNote: "saw their passport",
      contact: "reach me at someone@example.com or +90 555 111 22 33",
    });
    assert.equal(out.reasonCode, "SPAM");
    for (const k of ["password", "idToken", "otp", "authorization", "messageText", "ciphertext", "documentNumber", "selfieUrl", "rawPayload", "internalNote"]) {
      assert.equal(k in out, false, k);
    }
    assert.equal(out.internalNoteLength, "saw their passport".length);
    assert.doesNotMatch(out.contact, /someone@example\.com/);
    assert.doesNotMatch(out.contact, /555 111 22 33/);
  });

  it("events are append-only: a second write to the same id fails", async () => {
    const w = await world();
    const writer = {create: (ref, data) => ref.create(data)};
    const id = appendAuditEvent(writer, w.db, {actorAdminId: "mod-1", action: "CASE_ASSIGNED", targetType: "case", targetId: "c1"}, w.now);
    assert.ok(id.startsWith("aud_"));
    await new Promise((r) => setTimeout(r, 0));
    await assert.rejects(w.db.doc(`adminAuditLog/${id}`).create({action: "tampered"}));
  });

  it("no admin code path updates or deletes an audit event", () => {
    const adminDir = path.join(__dirname, "..", "src", "admin");
    const walk = (dir) => fs.readdirSync(dir, {withFileTypes: true}).flatMap((e) =>
      e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]);
    for (const file of walk(adminDir)) {
      if (file.endsWith("retention.ts")) {
        continue; // the documented, scheduled retention sweep is the only deleter
      }
      const src = fs.readFileSync(file, "utf8");
      assert.doesNotMatch(src, /adminAuditLog\/[^`"']*`\)\.(set|update|delete)\(/, file);
      assert.doesNotMatch(src, /AUDIT_COLLECTION\}\/[^`]*`\)\.(set|update|delete)\(/, file);
    }
  });

  it("revealing contact details needs user.read_sensitive, a justification, and is audited", async () => {
    const w = await world();
    const masked = await w.run(specs.adminGetUserOverviewSpec, "mod-1", {uid: "member-1"});
    assert.equal(masked.sensitiveIncluded, false);
    assert.doesNotMatch(String(masked.auth.email), /^member-1@example\.com$/);
    assert.match(String(masked.auth.phone), /\*/);
    assert.equal(events(w).length, 0, "an ordinary view is not a sensitive event");

    await rejectsWith(w.run(specs.adminGetUserOverviewSpec, "mod-1", {uid: "member-1", includeSensitive: true, justification: "support"}), "permission_denied");
    await rejectsWith(w.run(specs.adminGetUserOverviewSpec, "tsa-1", {uid: "member-1", includeSensitive: true}), "invalid_argument");

    const full = await w.run(specs.adminGetUserOverviewSpec, "tsa-1", {uid: "member-1", includeSensitive: true, justification: "ticket 123 identity check"});
    assert.equal(full.auth.email, "member-1@example.com");
    const sensitive = events(w).filter((e) => e.action === "SENSITIVE_PROFILE_VIEWED");
    assert.equal(sensitive.length, 1);
    assert.equal(sensitive[0].actorAdminId, "tsa-1");
    assert.equal(sensitive[0].metadata.justification, undefined, "justification text is not copied into the log");
  });

  it("audit events can be listed by staff with audit.read only", async () => {
    const w = await world();
    await w.run(specs.adminWarnUserSpec, "mod-1", {uid: "member-1", reasonCode: "SPAM", idempotencyKey: key()});
    await rejectsWith(w.run(specs.adminListAuditEventsSpec, "mod-1", {}), "permission_denied");
    const list = await w.run(specs.adminListAuditEventsSpec, "tsa-1", {targetId: "member-1"});
    assert.equal(list.items.length, 1);
    assert.equal(list.items[0].action, "USER_WARNED");
    await rejectsWith(w.run(specs.adminListAuditEventsSpec, "tsa-1", {targetId: "member-1", action: "USER_WARNED"}), "invalid_argument");
  });
});
