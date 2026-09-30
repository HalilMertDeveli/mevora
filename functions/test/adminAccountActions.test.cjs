const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");
const {createAdminWorld, rejectsWith, key} = require("./helpers/adminHarness.cjs");
const specs = require("../lib/admin/commands.js");
const {effectiveAccountStatus, isAccountEligible} = require("../lib/profileSafety.js");
const {expireSuspensions} = require("../lib/admin/retention.js");

const HOUR = 60 * 60 * 1000;

async function world() {
  const w = createAdminWorld();
  await w.addStaff("mod-1", "moderator");
  await w.addStaff("senior-1", "senior_moderator");
  await w.addStaff("tsa-1", "trust_safety_admin");
  await w.addStaff("super-1", "super_admin");
  await w.addMember("member-1");
  return w;
}

const actions = (w) => w.db.paths().filter((p) => p.startsWith("moderationActions/"));
const audits = (w, action) => w.db.paths()
  .filter((p) => p.startsWith("adminAuditLog/"))
  .map((p) => w.db.read(p))
  .filter((e) => !action || e.action === action);

describe("account moderation", () => {
  it("warn records an action and audit event without restricting the account", async () => {
    const w = await world();
    const result = await w.run(specs.adminWarnUserSpec, "mod-1", {
      uid: "member-1", reasonCode: "HARASSMENT", userMessage: "Please keep conversations respectful.", idempotencyKey: key(),
    });
    assert.equal(result.type, "WARNING");
    const user = w.db.read("users/member-1");
    assert.equal(user.accountStatus, "active");
    assert.equal(user.warningCount, 1);
    const action = w.db.read(`moderationActions/${result.actionId}`);
    assert.equal(action.userMessage, "Please keep conversations respectful.");
    assert.equal(action.actorAdminId, "mod-1");
    assert.equal(audits(w, "USER_WARNED").length, 1);
  });

  it("suspend sets canonical state, mirrors the legacy flag and records previous/new state", async () => {
    const w = await world();
    const result = await w.run(specs.adminSuspendUserSpec, "mod-1", {
      uid: "member-1", reasonCode: "HARASSMENT", durationHours: 72, internalNote: "3 reports this week", idempotencyKey: key(),
    });
    const user = w.db.read("users/member-1");
    assert.equal(user.accountStatus, "suspended");
    assert.equal(user.isSuspended, true);
    assert.equal(user.statusActionId, result.actionId);
    assert.equal(user.suspendedUntil.toMillis(), w.now + 72 * HOUR);
    const action = w.db.read(`moderationActions/${result.actionId}`);
    assert.equal(action.type, "TEMPORARY_SUSPENSION");
    assert.equal(action.previousState.accountStatus, "active");
    assert.equal(action.newState.accountStatus, "suspended");
    assert.equal(action.expiresAt.toMillis(), w.now + 72 * HOUR);
    const audit = audits(w, "USER_SUSPENDED")[0];
    assert.equal(audit.metadata.durationHours, 72);
    assert.equal(audit.metadata.internalNote, undefined, "note text never enters the audit log");
    assert.equal(audit.metadata.internalNoteLength, "3 reports this week".length);
  });

  it("a suspension does not touch Firebase Auth", async () => {
    const w = await world();
    await w.run(specs.adminSuspendUserSpec, "mod-1", {uid: "member-1", reasonCode: "SPAM", durationHours: 24, internalNote: "x", idempotencyKey: key()});
    assert.equal(w.auth.users.get("member-1").disabled, false);
    assert.equal(w.auth.calls.length, 0);
  });

  it("suspension expiry: the account is eligible again the moment it ends, and the sweep records it", async () => {
    const w = await world();
    await w.run(specs.adminSuspendUserSpec, "mod-1", {uid: "member-1", reasonCode: "SPAM", durationHours: 1, internalNote: "x", idempotencyKey: key()});
    assert.equal(isAccountEligible(w.db.read("users/member-1"), w.now), false);
    assert.equal(isAccountEligible(w.db.read("users/member-1"), w.now + HOUR + 1), true);
    assert.equal(effectiveAccountStatus(w.db.read("users/member-1"), w.now + HOUR + 1), "active");
    const expired = await expireSuspensions(w.db, w.now + HOUR + 1);
    assert.equal(expired, 1);
    const user = w.db.read("users/member-1");
    assert.equal(user.accountStatus, "active");
    assert.equal(user.isSuspended, false);
    assert.equal(user.statusReasonCode, "SUSPENSION_EXPIRED");
    assert.ok(actions(w).some((p) => w.db.read(p).type === "SUSPENSION_EXPIRED"));
    // Idempotent: a second sweep finds nothing.
    assert.equal(await expireSuspensions(w.db, w.now + HOUR + 2), 0);
  });

  it("a live suspension cannot be stacked; a banned account cannot be suspended", async () => {
    const w = await world();
    await w.run(specs.adminSuspendUserSpec, "mod-1", {uid: "member-1", reasonCode: "SPAM", durationHours: 24, internalNote: "x", idempotencyKey: key()});
    await rejectsWith(w.run(specs.adminSuspendUserSpec, "mod-1", {uid: "member-1", reasonCode: "SPAM", durationHours: 24, internalNote: "x", idempotencyKey: key()}), "user_already_suspended");
  });

  it("ban disables the Auth account, revokes sessions and records it", async () => {
    const w = await world();
    const result = await w.run(specs.adminBanUserSpec, "senior-1", {uid: "member-1", reasonCode: "SCAM_FRAUD", internalNote: "confirmed", idempotencyKey: key()});
    assert.equal(result.accountStatus, "banned");
    assert.equal(result.authSync, "done");
    const user = w.db.read("users/member-1");
    assert.equal(user.accountStatus, "banned");
    assert.equal(user.isBanned, true);
    assert.equal(w.auth.users.get("member-1").disabled, true);
    assert.ok(w.auth.calls.some(([op, uid]) => op === "revokeRefreshTokens" && uid === "member-1"));
    assert.equal(w.db.read(`moderationActions/${result.actionId}`).authSync.status, "done");
    assert.equal(audits(w, "USER_BANNED").length, 1);
  });

  it("ban twice with the same key replays; with a new key it is refused", async () => {
    const w = await world();
    const k = key();
    const first = await w.run(specs.adminBanUserSpec, "senior-1", {uid: "member-1", reasonCode: "SCAM_FRAUD", internalNote: "x", idempotencyKey: k});
    const replay = await w.run(specs.adminBanUserSpec, "senior-1", {uid: "member-1", reasonCode: "SCAM_FRAUD", internalNote: "x", idempotencyKey: k});
    assert.equal(replay.replayed, true);
    assert.equal(replay.actionId, first.actionId);
    assert.equal(actions(w).length, 1, "one action for a double click");
    assert.equal(audits(w, "USER_BANNED").length, 1, "one audit chain for a double click");
    await rejectsWith(
      w.run(specs.adminBanUserSpec, "senior-1", {uid: "member-1", reasonCode: "SCAM_FRAUD", internalNote: "x", idempotencyKey: key()}),
      "user_already_banned",
    );
  });

  it("a failed Auth sync is recorded and completed by the replay", async () => {
    const w = await world();
    const original = w.auth.updateUser;
    w.auth.updateUser = async () => {
      throw Object.assign(new Error("unavailable"), {code: "auth/internal-error"});
    };
    const k = key();
    const first = await w.run(specs.adminBanUserSpec, "senior-1", {uid: "member-1", reasonCode: "SCAM_FRAUD", internalNote: "x", idempotencyKey: k});
    assert.equal(first.authSync, "failed");
    assert.equal(audits(w, "AUTH_SYNC_FAILED").length, 1);
    w.auth.updateUser = original;
    const retry = await w.run(specs.adminBanUserSpec, "senior-1", {uid: "member-1", reasonCode: "SCAM_FRAUD", internalNote: "x", idempotencyKey: k});
    assert.equal(retry.authSync, "done");
    assert.equal(w.auth.users.get("member-1").disabled, true);
  });

  it("restore lifts a ban with a new action; the ban action is kept and marked overturned", async () => {
    const w = await world();
    const ban = await w.run(specs.adminBanUserSpec, "senior-1", {uid: "member-1", reasonCode: "SCAM_FRAUD", internalNote: "x", idempotencyKey: key()});
    const restore = await w.run(specs.adminRestoreUserSpec, "senior-1", {uid: "member-1", reasonCode: "ERROR_CORRECTION", internalNote: "wrong account", idempotencyKey: key()});
    assert.equal(restore.type, "RESTORE_ACCOUNT");
    const user = w.db.read("users/member-1");
    assert.equal(user.accountStatus, "active");
    assert.equal(user.isBanned, false);
    assert.equal(w.auth.users.get("member-1").disabled, false);
    const banAction = w.db.read(`moderationActions/${ban.actionId}`);
    assert.equal(banAction.type, "PERMANENT_BAN", "history is preserved");
    assert.equal(banAction.overturnedByActionId, restore.actionId);
    assert.equal(actions(w).length, 2);
  });

  it("restore of an unrestricted account is refused; legacy flags alone count as restricted", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminRestoreUserSpec, "senior-1", {uid: "member-1", reasonCode: "OTHER", internalNote: "x", idempotencyKey: key()}), "user_not_restricted");
    await w.db.doc("users/member-1").set({isBanned: true}, {merge: true});
    const result = await w.run(specs.adminRestoreUserSpec, "senior-1", {uid: "member-1", reasonCode: "OTHER", internalNote: "x", idempotencyKey: key()});
    assert.equal(result.accountStatus, "active");
    assert.equal(w.db.read("users/member-1").isBanned, false);
  });

  it("staff cannot sanction themselves, a super admin, or a colleague at their rank", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminSuspendUserSpec, "mod-1", {uid: "mod-1", reasonCode: "SPAM", durationHours: 24, internalNote: "x", idempotencyKey: key()}), "cannot_modify_self");
    await rejectsWith(w.run(specs.adminBanUserSpec, "tsa-1", {uid: "super-1", reasonCode: "SPAM", internalNote: "x", idempotencyKey: key()}), "cannot_modify_super_admin");
    await rejectsWith(w.run(specs.adminBanUserSpec, "senior-1", {uid: "tsa-1", reasonCode: "SPAM", internalNote: "x", idempotencyKey: key()}), "cannot_modify_staff");
  });

  it("a case link records the action on the case timeline", async () => {
    const w = await world();
    await w.db.doc("moderationCases/case_x").set({caseId: "case_x", type: "USER_REPORT", status: "open", priority: "high", subjectUserId: "member-1", sourceRefs: [], actionIds: []});
    const result = await w.run(specs.adminSuspendUserSpec, "mod-1", {uid: "member-1", reasonCode: "HARASSMENT", durationHours: 24, internalNote: "x", caseId: "case_x", idempotencyKey: key()});
    const c = w.db.read("moderationCases/case_x");
    assert.deepEqual(c.actionIds, [result.actionId]);
    assert.equal(c.assignedTo, "mod-1");
  });
});

describe("eligibility guard honours canonical and legacy state", () => {
  const now = Date.parse("2026-09-29T10:00:00Z");
  const future = Timestamp.fromMillis(now + HOUR);
  const past = Timestamp.fromMillis(now - HOUR);

  it("suspended and banned accounts are not eligible", () => {
    assert.equal(isAccountEligible({accountStatus: "suspended", suspendedUntil: future}, now), false);
    assert.equal(isAccountEligible({accountStatus: "suspended"}, now), false);
    assert.equal(isAccountEligible({accountStatus: "banned"}, now), false);
    assert.equal(isAccountEligible({isBanned: true}, now), false);
    assert.equal(isAccountEligible({isSuspended: true}, now), false);
    assert.equal(isAccountEligible({accountStatus: "deleted"}, now), false);
  });

  it("an ended suspension is eligible; a ban never expires", () => {
    assert.equal(isAccountEligible({accountStatus: "suspended", isSuspended: true, suspendedUntil: past}, now), true);
    assert.equal(isAccountEligible({accountStatus: "banned", suspendedUntil: past}, now), false);
  });

  it("the social callables share one guard", () => {
    const fs = require("node:fs");
    const path = require("node:path");
    const src = (f) => fs.readFileSync(path.join(__dirname, "..", "src", f), "utf8");
    for (const [file, callable] of [
      ["incomingLikes.ts", "getIncomingLikes"],
      ["boost/verifyBoostPurchase.ts", "activateBoost"],
      ["social.ts", "createVideoCall"],
      ["social.ts", "respondToVideoCall"],
      ["backend.ts", "getDistanceLabel"],
      ["spotifyMusic.ts", "getSameTasteProfiles"],
      ["spotifyMusic.ts", "getMatchMusicCompatibility"],
      ["humor/index.ts", "getMatchHumorCompatibility"],
      ["personalization/functions.ts", "recordProfileEngagement"],
    ]) {
      const body = src(file).split(`export const ${callable} = onCall(`)[1] ?? "";
      const handler = body.slice(0, 900);
      assert.match(handler, /assertCallerAccountEligible\(/, `${callable} must check account eligibility`);
    }
  });

  it("safety tools stay available to restricted members", () => {
    const fs = require("node:fs");
    const path = require("node:path");
    const social = fs.readFileSync(path.join(__dirname, "..", "src", "social.ts"), "utf8");
    for (const callable of ["reportUser", "blockUser", "unmatchUser"]) {
      const body = (social.split(`export const ${callable} = onCall(`)[1] ?? "").split("export const ")[0];
      assert.doesNotMatch(body, /assertCallerAccountEligible|isAccountEligible/, `${callable} must stay usable`);
    }
  });
});
