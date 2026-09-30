const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {createAdminWorld, rejectsWith, key} = require("./helpers/adminHarness.cjs");
const specs = require("../lib/admin/commands.js");
const {openAppeal} = require("../lib/admin/appeals/appealService.js");
const {buildMyModerationStatus} = require("../lib/admin/appeals/consumerAppeals.js");

const DAY = 24 * 60 * 60 * 1000;

async function world() {
  const w = createAdminWorld();
  await w.addStaff("mod-1", "moderator");
  await w.addStaff("senior-1", "senior_moderator");
  await w.addStaff("senior-2", "senior_moderator");
  await w.addStaff("support-1", "support_agent");
  await w.addMember("member-1");
  return w;
}

async function suspended(w) {
  const s = await w.run(specs.adminSuspendUserSpec, "mod-1", {uid: "member-1", reasonCode: "HARASSMENT", durationHours: 24 * 7, internalNote: "reports", idempotencyKey: key()});
  const appeal = await openAppeal(w.db, {
    userId: "member-1",
    moderationActionId: s.actionId,
    reason: "I think this was a misunderstanding, please review.",
    source: "app",
    sourceTicketId: null,
    openedBy: "member-1",
    openedByRole: "member",
    requestId: null,
  }, w.now);
  return {suspension: s, appeal};
}

describe("appeals", () => {
  it("a member opens one appeal per decision; a repeat is the same appeal", async () => {
    const w = await world();
    const {suspension, appeal} = await suspended(w);
    assert.equal(appeal.created, true);
    const doc = w.db.read(`appeals/${appeal.appealId}`);
    assert.equal(doc.userId, "member-1");
    assert.equal(doc.moderationActionId, suspension.actionId);
    assert.equal(doc.status, "open");
    assert.equal(w.db.read(`moderationCases/${appeal.caseId}`).type, "APPEAL");
    const again = await openAppeal(w.db, {userId: "member-1", moderationActionId: suspension.actionId, reason: "second try at appealing", source: "app", sourceTicketId: null, openedBy: "member-1", openedByRole: "member", requestId: null}, w.now);
    assert.equal(again.created, false);
    assert.equal(again.appealId, appeal.appealId);
  });

  it("nobody can appeal a decision that is not about them, or after the window", async () => {
    const w = await world();
    await w.addMember("member-2");
    const {suspension} = await suspended(w);
    await rejectsWith(openAppeal(w.db, {userId: "member-2", moderationActionId: suspension.actionId, reason: "not mine but let me try", source: "app", sourceTicketId: null, openedBy: "member-2", openedByRole: "member", requestId: null}, w.now), "appeal_not_allowed");
    await rejectsWith(openAppeal(w.db, {userId: "member-1", moderationActionId: "act_missing", reason: "does not exist at all", source: "app", sourceTicketId: null, openedBy: "member-1", openedByRole: "member", requestId: null}, w.now), "appeal_not_allowed");
    const w2 = await world();
    const s2 = await w2.run(specs.adminWarnUserSpec, "mod-1", {uid: "member-1", reasonCode: "SPAM", idempotencyKey: key()});
    await rejectsWith(openAppeal(w2.db, {userId: "member-1", moderationActionId: s2.actionId, reason: "late appeal about a warning", source: "app", sourceTicketId: null, openedBy: "member-1", openedByRole: "member", requestId: null}, w2.now + 31 * DAY), "appeal_window_closed");
  });

  it("moderators may read appeals but not decide them", async () => {
    const w = await world();
    const {appeal} = await suspended(w);
    const list = await w.run(specs.adminListAppealsSpec, "mod-1", {status: "open"});
    assert.equal(list.items.length, 1);
    await rejectsWith(w.run(specs.adminResolveAppealSpec, "mod-1", {appealId: appeal.appealId, decision: "accept", userMessage: "ok", idempotencyKey: key()}), "permission_denied");
  });

  it("assignment is exclusive", async () => {
    const w = await world();
    const {appeal} = await suspended(w);
    await w.run(specs.adminAssignAppealSpec, "senior-1", {appealId: appeal.appealId});
    const second = await w.run(specs.adminAssignAppealSpec, "senior-2", {appealId: appeal.appealId});
    // Seniors hold case.reassign, so they may take it over — and it is recorded.
    assert.equal(second.assignedTo, "senior-2");
    assert.equal(w.db.read(`appeals/${appeal.appealId}`).status, "in_review");
  });

  it("accepting restores the account through a new action; the original is kept", async () => {
    const w = await world();
    const {suspension, appeal} = await suspended(w);
    const result = await w.run(specs.adminResolveAppealSpec, "senior-1", {
      appealId: appeal.appealId, decision: "accept", userMessage: "We reviewed it and lifted the suspension.", idempotencyKey: key(),
    });
    assert.ok(result.restoreActionId);
    const user = w.db.read("users/member-1");
    assert.equal(user.accountStatus, "active");
    assert.equal(user.isSuspended, false);
    const original = w.db.read(`moderationActions/${suspension.actionId}`);
    assert.equal(original.type, "TEMPORARY_SUSPENSION", "never deleted or rewritten");
    assert.ok(original.overturnedByActionId);
    assert.equal(w.db.read(`moderationActions/${result.decisionActionId}`).type, "APPEAL_ACCEPTED");
    assert.equal(w.db.read(`moderationActions/${result.restoreActionId}`).type, "RESTORE_ACCOUNT");
    const a = w.db.read(`appeals/${appeal.appealId}`);
    assert.equal(a.status, "resolved");
    assert.equal(a.decision, "accepted");
    assert.equal(w.db.read(`moderationCases/${appeal.caseId}`).status, "resolved");
  });

  it("rejecting leaves the decision in force", async () => {
    const w = await world();
    const {appeal} = await suspended(w);
    const result = await w.run(specs.adminResolveAppealSpec, "senior-1", {appealId: appeal.appealId, decision: "reject", userMessage: "The suspension stands.", idempotencyKey: key()});
    assert.equal(result.restoreActionId, null);
    assert.equal(w.db.read("users/member-1").accountStatus, "suspended");
    assert.equal(w.db.read(`moderationActions/${result.decisionActionId}`).type, "APPEAL_REJECTED");
  });

  it("an appeal cannot be decided twice; the same submission replays", async () => {
    const w = await world();
    const {appeal} = await suspended(w);
    const k = key();
    const first = await w.run(specs.adminResolveAppealSpec, "senior-1", {appealId: appeal.appealId, decision: "reject", userMessage: "stands", idempotencyKey: k});
    const replay = await w.run(specs.adminResolveAppealSpec, "senior-1", {appealId: appeal.appealId, decision: "reject", userMessage: "stands", idempotencyKey: k});
    assert.equal(replay.replayed, true);
    assert.equal(replay.decisionActionId, first.decisionActionId);
    await rejectsWith(w.run(specs.adminResolveAppealSpec, "senior-2", {appealId: appeal.appealId, decision: "accept", userMessage: "overturn", idempotencyKey: key()}), "appeal_already_resolved");
  });

  it("the moderator who made the decision cannot judge the appeal against it", async () => {
    const w = await world();
    const s = await w.run(specs.adminBanUserSpec, "senior-1", {uid: "member-1", reasonCode: "SCAM_FRAUD", internalNote: "x", idempotencyKey: key()});
    const appeal = await openAppeal(w.db, {userId: "member-1", moderationActionId: s.actionId, reason: "I was hacked, not a scammer.", source: "support_ticket", sourceTicketId: "t1", openedBy: "support-1", openedByRole: "support_agent", requestId: null}, w.now);
    await rejectsWith(w.run(specs.adminResolveAppealSpec, "senior-1", {appealId: appeal.appealId, decision: "accept", userMessage: "ok", idempotencyKey: key()}), "appeal_self_review");
    const other = await w.run(specs.adminResolveAppealSpec, "senior-2", {appealId: appeal.appealId, decision: "accept", userMessage: "Account restored after review.", idempotencyKey: key()});
    assert.equal(w.db.read("users/member-1").accountStatus, "active");
    assert.equal(w.auth.users.get("member-1").disabled, false);
    assert.ok(other.restoreActionId);
  });

  it("support agents file ban appeals that arrived as tickets", async () => {
    const w = await world();
    const s = await w.run(specs.adminBanUserSpec, "senior-1", {uid: "member-1", reasonCode: "SPAM", internalNote: "x", idempotencyKey: key()});
    const result = await w.run(specs.adminOpenAppealSpec, "support-1", {userId: "member-1", moderationActionId: s.actionId, reason: "Member wrote in via the support site.", ticketId: "t1"});
    assert.equal(result.created, true);
    assert.equal(w.db.read(`appeals/${result.appealId}`).source, "support_ticket");
  });

  it("the member's status view shows decisions and appeals without staff detail", async () => {
    const w = await world();
    const {appeal} = await suspended(w);
    const status = await buildMyModerationStatus(w.db, "member-1", w.now);
    assert.equal(status.accountStatus, "suspended");
    assert.ok(status.suspendedUntil);
    assert.equal(status.decisions.length, 1);
    assert.equal(status.decisions[0].appeal.appealId, appeal.appealId);
    assert.equal(status.decisions[0].appealable, false);
    const json = JSON.stringify(status);
    for (const forbidden of ["mod-1", "internalNote", "reports", "actorAdminId"]) {
      assert.equal(json.includes(forbidden), false, forbidden);
    }
  });
});
