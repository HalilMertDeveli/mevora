const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const specs = require("../lib/admin/commands.js");
const {PERMISSIONS} = require("../lib/admin/auth/permissions.js");

/**
 * Structural guarantees about what the admin platform can and cannot do.
 * These fail the build if someone adds a generic write endpoint, a chat
 * reader, or a command without a declared permission.
 */
const allSpecs = Object.values(specs).filter((s) => s && typeof s === "object" && typeof s.name === "string");
const adminSrc = path.join(__dirname, "..", "src", "admin");
const walk = (dir) => fs.readdirSync(dir, {withFileTypes: true}).flatMap((e) =>
  e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]);
const sources = walk(adminSrc).map((file) => ({file, src: fs.readFileSync(file, "utf8")}));

describe("admin command surface", () => {
  it("has the full command set, each with exactly one known permission", () => {
    assert.ok(allSpecs.length >= 50, `only ${allSpecs.length} commands`);
    for (const spec of allSpecs) {
      assert.ok(PERMISSIONS.includes(spec.permission), `${spec.name}: ${spec.permission}`);
      assert.equal(typeof spec.parse, "function", spec.name);
      assert.equal(typeof spec.handler, "function", spec.name);
      assert.ok(["read", "search", "mutation", "sensitive"].includes(spec.rateClass), spec.name);
    }
    const names = new Set(allSpecs.map((s) => s.name));
    for (const required of [
      "adminSearchUsers", "adminGetUserOverview", "adminGetUserSafetyTimeline",
      "adminListCases", "adminGetCase", "adminAssignCase", "adminResolveCase", "adminEscalateCase", "adminAddCaseNote",
      "adminListReports", "adminResolveUserReport",
      "adminListPhotoReviews", "adminReviewPhoto",
      "adminListHumorReviews", "adminReviewHumorContent", "adminListHumorCoreSequence",
      "adminWarnUser", "adminSuspendUser", "adminBanUser", "adminRestoreUser",
      "adminGetVerification", "adminRequireReverification",
      "adminListSupportTickets", "adminGetSupportTicket", "adminAssignSupportTicket", "adminReplySupportTicket", "adminResolveSupportTicket",
      "adminListManualReviewJobs", "adminReviewAutomationJob",
      "adminListAppeals", "adminResolveAppeal",
      "adminListAuditEvents",
      "adminListStaff", "adminUpdateStaffRole", "adminDisableStaff",
    ]) {
      assert.ok(names.has(required), required);
    }
  });

  it("every spec is exported as a deployable callable under its own name", () => {
    const index = fs.readFileSync(path.join(adminSrc, "index.ts"), "utf8");
    for (const spec of allSpecs) {
      assert.match(index, new RegExp(`export const ${spec.name} = defineAdminCommand\\(`), spec.name);
    }
  });

  it("can read the Humor Core sequence but has no command that changes it", () => {
    const core = allSpecs.filter((spec) => /core/i.test(spec.name));
    assert.deepEqual(core.map((spec) => spec.name), ["adminListHumorCoreSequence"]);
    assert.equal(core[0].permission, "humor.read");
    assert.equal(core[0].rateClass, "read");
    // The order is code, frozen by a lock fixture: no admin module writes it.
    for (const {file, src} of sources) {
      assert.doesNotMatch(src, /humor\/core["'`]\)\.(set|update|delete|create)\(/, file);
      assert.doesNotMatch(src, /HUMOR_CORE_SEQUENCE\s*(\.push|\[|=)/, file);
    }
  });

  it("offers no generic write-anything command", () => {
    for (const spec of allSpecs) {
      assert.doesNotMatch(spec.name, /write|updatedocument|setdocument|anything|rawquery|firestore|execute/i, spec.name);
    }
  });

  it("never reads private chat: no admin module touches matches/*/messages or E2EE keys", () => {
    for (const {file, src} of sources) {
      assert.doesNotMatch(src, /collection\(\s*["'`]messages["'`]\s*\)[\s\S]{0,40}matches|matches\/\$\{[^}]+\}\/messages/, file);
      assert.doesNotMatch(src, /\/crypto\/|privateKey|\bdecrypt\w*\(/i, file);
    }
    for (const spec of allSpecs) {
      assert.doesNotMatch(spec.name, /chat|conversation|message(s)?history|decrypt/i, spec.name);
    }
  });

  it("never writes the client-facing photos array as its authority", () => {
    for (const {file, src} of sources) {
      // Admin photo decisions go through setPhotoModerationStatus (ledger first).
      assert.doesNotMatch(src, /profiles\/\$\{[^}]+\}`\)[\s\S]{0,80}photos:/, file);
    }
  });

  it("admin commands skip App Check only because the BFF credential replaces it", () => {
    const command = fs.readFileSync(path.join(adminSrc, "command.ts"), "utf8");
    assert.match(command, /enforceAppCheck: false/);
    assert.match(command, /secrets: \[adminBffSecret\]/);
    const consumer = fs.readFileSync(path.join(adminSrc, "appeals", "consumerAppeals.ts"), "utf8");
    assert.match(consumer, /enforceAppCheck = process\.env\.FUNCTIONS_EMULATOR !== "true"/);
  });
});
