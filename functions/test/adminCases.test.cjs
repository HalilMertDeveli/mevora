const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {createAdminWorld, rejectsWith} = require("./helpers/adminHarness.cjs");
const specs = require("../lib/admin/commands.js");
const {openOrAttachCase} = require("../lib/admin/cases/caseService.js");
const {intakeUserReport} = require("../lib/admin/reports/reportIntake.js");
const {canTransition, CASE_TRANSITIONS} = require("../lib/admin/cases/caseTypes.js");
const {reportPriority} = require("../lib/admin/reports/reportPriority.js");

async function world() {
  const w = createAdminWorld();
  await w.addStaff("mod-1", "moderator");
  await w.addStaff("mod-2", "moderator");
  await w.addStaff("senior-1", "senior_moderator");
  await w.addStaff("support-1", "support_agent");
  await w.addMember("bad-actor");
  await w.addMember("reporter-1");
  await w.addMember("reporter-2");
  await w.addMember("reporter-3");
  return w;
}

async function fileReport(w, id, {reporter = "reporter-1", reported = "bad-actor", reason = "harassment"} = {}) {
  const {priority, priorityRank} = reportPriority(reason);
  await w.db.doc(`reports/${id}`).set({
    reporterId: reporter,
    reportedUserId: reported,
    reason,
    description: "they keep messaging me",
    matchId: "m1",
    messageId: "msg1",
    priority,
    priorityRank,
    status: "open",
    createdAt: new Date(w.now),
  });
  return intakeUserReport(w.db, {reportId: id, reporterId: reporter, reportedUserId: reported, reason}, w.now);
}

describe("report priority is decided server-side", () => {
  it("maps the production reason whitelist", () => {
    assert.equal(reportPriority("child_safety").priority, "critical");
    assert.equal(reportPriority("underage").priority, "critical");
    assert.equal(reportPriority("harassment").priority, "high");
    assert.equal(reportPriority("scam").priority, "high");
    assert.equal(reportPriority("inappropriate_content").priority, "high");
    assert.equal(reportPriority("fake_profile").priority, "medium");
    assert.equal(reportPriority("spam").priority, "normal");
    assert.equal(reportPriority("other").priority, "normal");
    assert.equal(reportPriority("made-up").priority, "normal");
  });
});

describe("case intake and correlation", () => {
  it("creates a case and links the report to it", async () => {
    const w = await world();
    const {caseId} = await fileReport(w, "r1");
    const c = w.db.read(`moderationCases/${caseId}`);
    assert.equal(c.type, "USER_REPORT");
    assert.equal(c.subjectUserId, "bad-actor");
    assert.equal(c.status, "open");
    assert.equal(c.priority, "high");
    assert.deepEqual(c.sourceRefs, ["reports/r1"]);
    assert.equal(w.db.read("reports/r1").caseId, caseId);
    // The original report is untouched apart from server-owned fields.
    assert.equal(w.db.read("reports/r1").description, "they keep messaging me");
  });

  it("attaches repeat reports of the same concern to the open case", async () => {
    const w = await world();
    const a = await fileReport(w, "r1", {reporter: "reporter-1"});
    const b = await fileReport(w, "r2", {reporter: "reporter-2"});
    assert.equal(a.caseId, b.caseId);
    const c = w.db.read(`moderationCases/${a.caseId}`);
    assert.deepEqual(c.sourceRefs.sort(), ["reports/r1", "reports/r2"]);
    assert.equal(c.sourceCount, 2);
    assert.equal(c.reporterCount, 2);
  });

  it("never swallows a different, more serious concern into an open case", async () => {
    const w = await world();
    const spam = await fileReport(w, "r1", {reason: "spam"});
    const underage = await fileReport(w, "r2", {reason: "underage", reporter: "reporter-2"});
    assert.notEqual(spam.caseId, underage.caseId);
    assert.equal(w.db.read(`moderationCases/${underage.caseId}`).priority, "critical");
  });

  it("three distinct reporters raise the priority one level", async () => {
    const w = await world();
    const {caseId} = await fileReport(w, "r1", {reason: "spam", reporter: "reporter-1"});
    await fileReport(w, "r2", {reason: "spam", reporter: "reporter-2"});
    assert.equal(w.db.read(`moderationCases/${caseId}`).priority, "normal");
    await fileReport(w, "r3", {reason: "spam", reporter: "reporter-3"});
    assert.equal(w.db.read(`moderationCases/${caseId}`).priority, "medium");
  });

  it("the same source is never attached twice", async () => {
    const w = await world();
    const first = await fileReport(w, "r1");
    const again = await openOrAttachCase(w.db, {
      type: "USER_REPORT",
      correlationKey: "user_report:bad-actor:harassment",
      subjectUserId: "bad-actor",
      sourceRef: "reports/r1",
      reasonCode: "harassment",
      priority: "high",
      reporterId: "reporter-1",
      createdBy: "system",
    }, w.now);
    assert.equal(again.caseId, first.caseId);
    assert.equal(w.db.read(`moderationCases/${first.caseId}`).sourceCount, 1);
  });

  it("after resolution, a new report opens a fresh case", async () => {
    const w = await world();
    const first = await fileReport(w, "r1");
    await w.run(specs.adminResolveCaseSpec, "mod-1", {caseId: first.caseId, outcome: "resolved", code: "no_violation"});
    const second = await fileReport(w, "r2", {reporter: "reporter-2"});
    assert.notEqual(second.caseId, first.caseId);
    assert.equal(w.db.read(`moderationCases/${first.caseId}`).status, "resolved");
  });
});

describe("case workflow", () => {
  it("assign → in_review → resolve closes the case and its reports", async () => {
    const w = await world();
    const {caseId} = await fileReport(w, "r1");
    await fileReport(w, "r2", {reporter: "reporter-2"});
    const assigned = await w.run(specs.adminAssignCaseSpec, "mod-1", {caseId});
    assert.equal(assigned.status, "assigned");
    assert.equal(assigned.assignedTo, "mod-1");
    await w.run(specs.adminSetCaseStatusSpec, "mod-1", {caseId, status: "in_review"});
    const resolved = await w.run(specs.adminResolveCaseSpec, "mod-1", {caseId, outcome: "resolved", code: "action_taken", note: "warned"});
    assert.equal(resolved.status, "resolved");
    assert.equal(resolved.reportsClosed, 2);
    assert.equal(w.db.read("reports/r1").status, "resolved");
    assert.equal(w.db.read("reports/r2").resolution, "action_taken");
    const c = w.db.read(`moderationCases/${caseId}`);
    assert.equal(c.resolvedBy, "mod-1");
    assert.deepEqual(c.resolution, {outcome: "resolved", code: "action_taken"});
  });

  it("two moderators claiming at once: exactly one wins, deterministically", async () => {
    const w = await world();
    const {caseId} = await fileReport(w, "r1");
    const results = await Promise.allSettled([
      w.run(specs.adminAssignCaseSpec, "mod-1", {caseId}),
      w.run(specs.adminAssignCaseSpec, "mod-2", {caseId}),
    ]);
    const won = results.filter((r) => r.status === "fulfilled");
    const lost = results.filter((r) => r.status === "rejected");
    assert.equal(won.length, 1);
    assert.equal(lost.length, 1);
    assert.equal(lost[0].reason.details.code, "case_already_assigned");
    assert.equal(w.db.read(`moderationCases/${caseId}`).assignedTo, won[0].value.assignedTo);
  });

  it("claiming a case you already hold is a no-op", async () => {
    const w = await world();
    const {caseId} = await fileReport(w, "r1");
    await w.run(specs.adminAssignCaseSpec, "mod-1", {caseId});
    const again = await w.run(specs.adminAssignCaseSpec, "mod-1", {caseId});
    assert.equal(again.changed, false);
  });

  it("a colleague cannot resolve a case somebody else holds without reassign rights", async () => {
    const w = await world();
    const {caseId} = await fileReport(w, "r1");
    await w.run(specs.adminAssignCaseSpec, "mod-1", {caseId});
    await rejectsWith(w.run(specs.adminResolveCaseSpec, "mod-2", {caseId, outcome: "dismissed", code: "no_violation"}), "case_already_assigned");
    // A senior moderator may take it over.
    await w.run(specs.adminAssignCaseSpec, "senior-1", {caseId});
    assert.equal(w.db.read(`moderationCases/${caseId}`).assignedTo, "senior-1");
  });

  it("closed cases refuse further transitions; a replayed resolution is idempotent", async () => {
    const w = await world();
    const {caseId} = await fileReport(w, "r1");
    await w.run(specs.adminResolveCaseSpec, "mod-1", {caseId, outcome: "dismissed", code: "no_violation"});
    const replay = await w.run(specs.adminResolveCaseSpec, "mod-1", {caseId, outcome: "dismissed", code: "no_violation"});
    assert.equal(replay.alreadyResolved, true);
    await rejectsWith(w.run(specs.adminResolveCaseSpec, "mod-1", {caseId, outcome: "resolved", code: "action_taken"}), "invalid_state_transition");
    await rejectsWith(w.run(specs.adminSetCaseStatusSpec, "mod-1", {caseId, status: "in_review"}), "invalid_state_transition");
    await rejectsWith(w.run(specs.adminAssignCaseSpec, "mod-1", {caseId}), "invalid_state_transition");
  });

  it("the state machine is finite: terminal states have no exits", () => {
    assert.deepEqual(CASE_TRANSITIONS.resolved, []);
    assert.deepEqual(CASE_TRANSITIONS.dismissed, []);
    assert.equal(canTransition("open", "resolved"), true);
    assert.equal(canTransition("resolved", "open"), false);
  });

  it("escalation raises priority, returns the case to the queue and records why", async () => {
    const w = await world();
    const {caseId} = await fileReport(w, "r1", {reason: "spam"});
    await w.run(specs.adminAssignCaseSpec, "mod-1", {caseId});
    const escalated = await w.run(specs.adminEscalateCaseSpec, "mod-1", {caseId, reason: "possible organised scam ring"});
    assert.equal(escalated.priority, "high");
    assert.equal(escalated.escalationLevel, 1);
    const c = w.db.read(`moderationCases/${caseId}`);
    assert.equal(c.status, "open");
    assert.equal(c.assignedTo, null);
    assert.equal(c.escalated, true);
  });

  it("internal notes are stored on the case, separate from any member-visible record", async () => {
    const w = await world();
    const {caseId} = await fileReport(w, "r1");
    const {noteId} = await w.run(specs.adminAddCaseNoteSpec, "mod-1", {caseId, text: "Screenshots checked, pattern matches prior case."});
    const note = w.db.read(`moderationCases/${caseId}/notes/${noteId}`);
    assert.equal(note.type, "internal_note");
    assert.equal(note.authorUid, "mod-1");
    assert.equal(note.text, "Screenshots checked, pattern matches prior case.");
    const detail = await w.run(specs.adminGetCaseSpec, "mod-1", {caseId});
    assert.ok(detail.timeline.some((t) => t.noteId === noteId));
    assert.ok(detail.timeline.some((t) => t.event === "created"));
  });

  it("support agents cannot work moderation cases", async () => {
    const w = await world();
    const {caseId} = await fileReport(w, "r1");
    await rejectsWith(w.run(specs.adminGetCaseSpec, "support-1", {caseId}), "permission_denied");
    await rejectsWith(w.run(specs.adminAssignCaseSpec, "support-1", {caseId}), "permission_denied");
  });
});

describe("queues are ordered and paginated", () => {
  it("the active case queue puts critical first, then oldest first, and pages with a cursor", async () => {
    const w = await world();
    await fileReport(w, "r-spam", {reason: "spam"});
    w.advance(1000);
    await fileReport(w, "r-fake", {reason: "fake_profile", reporter: "reporter-2"});
    w.advance(1000);
    await fileReport(w, "r-minor", {reason: "underage", reporter: "reporter-3"});
    const page1 = await w.run(specs.adminListCasesSpec, "mod-1", {limit: 2});
    assert.deepEqual(page1.items.map((c) => c.priority), ["critical", "medium"]);
    assert.ok(page1.nextCursor);
    const page2 = await w.run(specs.adminListCasesSpec, "mod-1", {limit: 2, cursor: page1.nextCursor});
    assert.deepEqual(page2.items.map((c) => c.priority), ["normal"]);
    assert.equal(page2.nextCursor, null);
  });

  it("the open report queue sorts by server-side priority and shows metadata only", async () => {
    const w = await world();
    await fileReport(w, "r1", {reason: "spam"});
    await fileReport(w, "r2", {reason: "underage", reporter: "reporter-2"});
    const queue = await w.run(specs.adminListReportsSpec, "mod-1", {});
    assert.deepEqual(queue.items.map((r) => r.reportId), ["r2", "r1"]);
    const row = queue.items[0];
    assert.equal(row.matchId, "m1");
    assert.equal(row.messageId, "msg1");
    // Only operational references: there is no message content field at all.
    for (const forbidden of ["text", "ciphertext", "message", "messageText", "body"]) {
      assert.equal(forbidden in row, false, forbidden);
    }
    assert.equal(row.reportedUser.uid, "bad-actor");
  });

  it("a malformed cursor is refused, not trusted", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminListCasesSpec, "mod-1", {cursor: "not-a-cursor"}), "invalid_argument");
  });
});
