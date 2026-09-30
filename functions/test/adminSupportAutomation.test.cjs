const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {createAdminWorld, rejectsWith, key} = require("./helpers/adminHarness.cjs");
const specs = require("../lib/admin/commands.js");
const {normalizeTicketStatus, normalizeTicketPriority} = require("../lib/admin/support/supportService.js");
const {allowedJobActions} = require("../lib/admin/automation/manualReviewQueue.js");
const {permissionsForRole} = require("../lib/admin/auth/roles.js");

async function world() {
  const w = createAdminWorld();
  await w.addStaff("support-1", "support_agent");
  await w.addStaff("support-2", "support_agent");
  await w.addStaff("mod-1", "moderator");
  await w.addStaff("tsa-1", "trust_safety_admin");
  await w.addMember("member-1");
  // An app ticket (rules-bound userId) and a website ticket (visitor-typed userId).
  await w.db.doc("supportTickets/app1").set({
    userId: "member-1", category: "safety", subject: "Someone is harassing me", message: "details",
    attachments: [], status: "open", createdAt: new Date(w.now - 5000), updatedAt: new Date(w.now - 5000),
  });
  await w.db.doc("supportTickets/web1").set({
    id: "web1", userId: "member-1", name: "Visitor", email: "visitor@example.com", category: "account_login",
    subject: "Cannot log in", description: "help", message: "help", priority: "Urgent", status: "Open",
    source: "website", attachments: [], createdAt: new Date(w.now - 1000), updatedAt: new Date(w.now - 1000),
  });
  return w;
}

describe("support tickets", () => {
  it("normalises both writers' vocabularies", () => {
    assert.equal(normalizeTicketStatus("Open"), "open");
    assert.equal(normalizeTicketStatus("InProgress"), "in_progress");
    assert.equal(normalizeTicketStatus("resolved"), "resolved");
    assert.equal(normalizeTicketPriority("Urgent"), "urgent");
    assert.equal(normalizeTicketPriority(undefined), "normal");
  });

  it("lists app and website tickets together; a website userId is flagged unverified", async () => {
    const w = await world();
    const list = await w.run(specs.adminListSupportTicketsSpec, "support-1", {status: "active"});
    assert.deepEqual(list.items.map((t) => t.ticketId), ["web1", "app1"]);
    const web = list.items.find((t) => t.ticketId === "web1");
    assert.equal(web.status, "open");
    assert.equal(web.priority, "urgent");
    assert.equal(web.userIdVerified, false);
    assert.equal(web.user, null, "an unverified userId is not joined to a member");
    assert.equal(list.items.find((t) => t.ticketId === "app1").userIdVerified, true);
  });

  it("a reply goes to the user-visible thread; an internal note never does", async () => {
    const w = await world();
    const reply = await w.run(specs.adminReplySupportTicketSpec, "support-1", {ticketId: "app1", text: "Thanks — we are looking into it.", idempotencyKey: key()});
    const note = await w.run(specs.adminAddSupportNoteSpec, "support-1", {ticketId: "app1", text: "Linked to case about the same user."});
    const message = w.db.read(`supportTickets/app1/messages/${reply.messageId}`);
    assert.equal(message.visibility, "user");
    assert.equal(message.type, "support");
    assert.equal(JSON.stringify(message).includes("support-1"), false, "the member never learns which agent replied");
    assert.equal(w.db.read(`supportTickets/app1/messages/${note.noteId}`), undefined);
    assert.equal(w.db.read(`supportTickets/app1/internalNotes/${note.noteId}`).text, "Linked to case about the same user.");
    const ticket = w.db.read("supportTickets/app1");
    assert.equal(ticket.status, "in_progress");
    assert.ok(ticket.firstResponseAt);
    assert.equal(ticket.assignedTo, "support-1");
    // The original fields the app reads are untouched.
    assert.equal(ticket.subject, "Someone is harassing me");
    assert.equal(ticket.message, "details");
  });

  it("a double-submitted reply is stored once", async () => {
    const w = await world();
    const k = key();
    await w.run(specs.adminReplySupportTicketSpec, "support-1", {ticketId: "app1", text: "Hello", idempotencyKey: k});
    const again = await w.run(specs.adminReplySupportTicketSpec, "support-1", {ticketId: "app1", text: "Hello", idempotencyKey: k});
    assert.equal(again.replayed, true);
    assert.equal(w.db.paths().filter((p) => p.startsWith("supportTickets/app1/messages/")).length, 1);
  });

  it("assign, resolve, close — and a closed ticket takes no more replies", async () => {
    const w = await world();
    await w.run(specs.adminAssignSupportTicketSpec, "support-1", {ticketId: "web1", assigneeUid: "support-2"});
    assert.equal(w.db.read("supportTickets/web1").assignedTo, "support-2");
    await w.run(specs.adminResolveSupportTicketSpec, "support-2", {ticketId: "web1", outcome: "resolved"});
    assert.equal(w.db.read("supportTickets/web1").status, "resolved");
    await w.run(specs.adminResolveSupportTicketSpec, "support-2", {ticketId: "web1", outcome: "closed"});
    await rejectsWith(w.run(specs.adminReplySupportTicketSpec, "support-2", {ticketId: "web1", text: "late", idempotencyKey: key()}), "ticket_closed");
  });

  it("escalation hands a verified member's ticket to Trust & Safety", async () => {
    const w = await world();
    const result = await w.run(specs.adminEscalateSupportTicketSpec, "support-1", {ticketId: "app1", reason: "harassment report", idempotencyKey: key()});
    const c = w.db.read(`moderationCases/${result.caseId}`);
    assert.equal(c.type, "SUPPORT_ESCALATION");
    assert.equal(c.subjectUserId, "member-1");
    assert.equal(w.db.read(`moderationActions/${result.actionId}`).type, "SUPPORT_ESCALATION");
    const web = await w.run(specs.adminEscalateSupportTicketSpec, "support-1", {ticketId: "web1", reason: "login", idempotencyKey: key()});
    assert.equal(web.actionId, null, "no action against a member the ticket cannot be tied to");
    assert.equal(w.db.read(`moderationCases/${web.caseId}`).subjectUserId, null);
  });

  it("attachment preview only serves paths that belong to the ticket", async () => {
    const w = await world();
    await w.db.doc("supportTickets/app1").set({attachments: ["users/member-1/support/app1/attachment.png", "users/other/support/x/a.png"]}, {merge: true});
    w.bucket.put("users/member-1/support/app1/attachment.png", [1, 2, 3], "image/png");
    w.bucket.put("users/other/support/x/a.png", [4, 5, 6], "image/png");
    const ok = await w.run(specs.adminGetSupportAttachmentSpec, "support-1", {ticketId: "app1", index: 0});
    assert.equal(ok.contentType, "image/png");
    await rejectsWith(w.run(specs.adminGetSupportAttachmentSpec, "support-1", {ticketId: "app1", index: 1}), "not_found");
  });

  it("moderators cannot answer customers", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminReplySupportTicketSpec, "mod-1", {ticketId: "app1", text: "x", idempotencyKey: key()}), "permission_denied");
  });
});

describe("automation manual review", () => {
  async function jobs() {
    const w = await world();
    await w.db.doc("automationJobs/deletion_verify_u1").set({
      jobId: "deletion_verify_u1", kind: "account_deletion_verify", status: "manual_review",
      requiresHumanReview: true, attempts: 5, maxAttempts: 5, payload: {uid: "u1"},
      result: {complete: false, issues: ["storage_remnant:users/u1/"], secretish: "should-not-show"},
      updatedAt: new Date(w.now), createdAt: new Date(w.now - 1000),
    });
    await w.db.doc("automationJobs/unknown_1").set({
      jobId: "unknown_1", kind: "some_future_kind", status: "manual_review", requiresHumanReview: true,
      updatedAt: new Date(w.now - 500), createdAt: new Date(w.now - 1000),
    });
    return w;
  }

  it("lists manual-review jobs with a safe result projection and per-kind actions", async () => {
    const w = await jobs();
    const list = await w.run(specs.adminListManualReviewJobsSpec, "tsa-1", {});
    const job = list.items.find((j) => j.jobId === "deletion_verify_u1");
    assert.deepEqual(job.allowedActions.sort(), ["escalate", "resolve", "retry"]);
    assert.equal("secretish" in job.result, false);
    const unknown = list.items.find((j) => j.jobId === "unknown_1");
    assert.deepEqual(unknown.allowedActions.sort(), ["dismiss", "escalate"], "no generic retry");
  });

  it("closing a compliance job needs automation.resolve_sensitive", () => {
    const actor = (role) => ({permissions: permissionsForRole(role)});
    assert.deepEqual(allowedJobActions("account_deletion_verify", actor("moderator")), ["escalate"]);
    assert.ok(allowedJobActions("account_deletion_verify", actor("trust_safety_admin")).includes("resolve"));
  });

  it("retry re-queues with a bounded budget; unsupported actions are refused", async () => {
    const w = await jobs();
    await w.run(specs.adminReviewAutomationJobSpec, "tsa-1", {jobId: "deletion_verify_u1", action: "retry", note: "storage outage is over"});
    const job = w.db.read("automationJobs/deletion_verify_u1");
    assert.equal(job.status, "retrying");
    assert.equal(job.requiresHumanReview, false);
    assert.equal(job.maxAttempts, 8);
    assert.equal(job.adminReview.by, "tsa-1");
    await rejectsWith(w.run(specs.adminReviewAutomationJobSpec, "tsa-1", {jobId: "unknown_1", action: "retry", note: "try anyway"}), "unsupported_job_action");
  });

  it("a moderator can escalate but not resolve a deletion job", async () => {
    const w = await jobs();
    await rejectsWith(w.run(specs.adminReviewAutomationJobSpec, "mod-1", {jobId: "deletion_verify_u1", action: "resolve", note: "looks fine"}), "permission_denied");
    const esc = await w.run(specs.adminReviewAutomationJobSpec, "mod-1", {jobId: "deletion_verify_u1", action: "escalate", note: "needs compliance"});
    assert.equal(w.db.read(`moderationCases/${esc.caseId}`).type, "AUTOMATION_REVIEW");
  });
});
