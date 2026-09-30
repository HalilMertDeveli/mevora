const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {createAdminWorld, rejectsWith, key, T0} = require("./helpers/adminHarness.cjs");
const specs = require("../lib/admin/commands.js");
const {AUDIT_SCAN_CAP} = require("../lib/admin/dashboard.js");

/**
 * Owner super admin + staff management (the S-matrix): who can add, change,
 * disable and sign out colleagues, what protects the owner, and that every
 * staff change lands in the audit log.
 */

async function world() {
  const w = createAdminWorld();
  await w.addStaff("owner-1", "super_admin", {isOwner: true});
  await w.addStaff("tsa-1", "trust_safety_admin");
  await w.addStaff("senior-1", "senior_moderator");
  await w.addStaff("mod-1", "moderator");
  await w.addStaff("support-1", "support_agent");
  await w.addMember("member-1");
  return w;
}

const events = (w) => w.db.paths().filter((p) => p.startsWith("adminAuditLog/")).map((p) => w.db.read(p));
const eventsFor = (w, action) => events(w).filter((e) => e.action === action);

function create(w, actor, over = {}) {
  return w.run(specs.adminCreateStaffSpec, actor, {
    email: "New.Colleague@Mevora.test",
    displayName: "New Colleague",
    role: "trust_safety_admin",
    idempotencyKey: key("create"),
    ...over,
  });
}

describe("owner model", () => {
  it("the owner flag is read from the staff record and reported on the profile", async () => {
    const w = await world();
    const me = await w.run(specs.adminGetMyStaffProfileSpec, "owner-1");
    assert.equal(me.isOwner, true);
    assert.equal(me.role, "super_admin");
    const tsa = await w.run(specs.adminGetMyStaffProfileSpec, "tsa-1");
    assert.equal(tsa.isOwner, false);
  });

  it("S18 the owner cannot act on their own staff record", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminDisableStaffSpec, "owner-1", {targetUid: "owner-1", reason: "oops"}), "cannot_modify_self");
    await rejectsWith(w.run(specs.adminUpdateStaffRoleSpec, "owner-1", {targetUid: "owner-1", role: "moderator"}), "cannot_modify_self");
    await rejectsWith(w.run(specs.adminRevokeStaffSessionsSpec, "owner-1", {targetUid: "owner-1", reason: "x"}), "cannot_modify_self");
    assert.equal(w.db.read("adminStaff/owner-1").status, "active");
  });

  it("no console command changes the owner, even from another super admin", async () => {
    const w = await world();
    await w.addStaff("super-2", "super_admin");
    await rejectsWith(w.run(specs.adminDisableStaffSpec, "super-2", {targetUid: "owner-1", reason: "x"}), "cannot_modify_owner");
    await rejectsWith(w.run(specs.adminUpdateStaffRoleSpec, "super-2", {targetUid: "owner-1", role: "moderator"}), "cannot_modify_owner");
    await rejectsWith(w.run(specs.adminRevokeStaffSessionsSpec, "super-2", {targetUid: "owner-1", reason: "x"}), "cannot_modify_owner");
    await rejectsWith(w.run(specs.adminIssueStaffActivationSpec, "super-2", {targetUid: "owner-1"}), "cannot_modify_owner");
    const owner = w.db.read("adminStaff/owner-1");
    assert.equal(owner.status, "active");
    assert.equal(owner.role, "super_admin");
    assert.equal(owner.isOwner, true);
  });

  it("the owner cannot be sanctioned as a member either", async () => {
    const w = await world();
    await rejectsWith(
      w.run(specs.adminSuspendUserSpec, "tsa-1", {uid: "owner-1", reasonCode: "SPAM", durationHours: 24, internalNote: "x", idempotencyKey: key()}),
      "cannot_modify_super_admin",
    );
    await rejectsWith(
      w.run(specs.adminBanUserSpec, "owner-1", {uid: "owner-1", reasonCode: "SPAM", internalNote: "x", idempotencyKey: key()}),
      "cannot_modify_self",
    );
  });

  it("S17 no console path creates a second super admin", async () => {
    const w = await world();
    await rejectsWith(create(w, "owner-1", {role: "super_admin"}), "invalid_argument");
    await rejectsWith(w.run(specs.adminUpdateStaffRoleSpec, "owner-1", {targetUid: "tsa-1", role: "super_admin"}), "role_grant_forbidden");
    assert.equal(w.db.read("adminStaff/tsa-1").role, "trust_safety_admin");
    const supers = w.db.paths().filter((p) => p.startsWith("adminStaff/")).map((p) => w.db.read(p)).filter((s) => s.role === "super_admin");
    assert.equal(supers.length, 1);
  });
});

describe("staff creation", () => {
  it("S2 the owner adds a Trust & Safety admin with a login nobody knows the password of", async () => {
    const w = await world();
    const result = await create(w, "owner-1");
    assert.equal(result.accountCreated, true);
    assert.equal(result.role, "trust_safety_admin");
    assert.equal(result.email, "new.colleague@mevora.test");
    assert.equal(result.password, undefined, "a password is never returned");
    const [, uid, props] = w.auth.calls.find(([op]) => op === "createUser");
    assert.equal(uid, result.uid);
    assert.equal(props.passwordSet, true);
    assert.equal(props.emailVerified, true);
    const staff = w.db.read(`adminStaff/${result.uid}`);
    assert.equal(staff.role, "trust_safety_admin");
    assert.equal(staff.status, "active");
    assert.equal(staff.isOwner, false);
    assert.equal(staff.createdBy, "owner-1");
    assert.deepEqual(w.auth.users.get(result.uid).customClaims, {admin: true, adminRole: "trust_safety_admin"});
    const [event] = eventsFor(w, "ADMIN_CREATED");
    assert.equal(event.targetId, result.uid);
    assert.equal(event.actorAdminId, "owner-1");
    assert.deepEqual(event.metadata, {role: "trust_safety_admin", accountCreated: true});
  });

  it("S3/S4 the new colleague can use the console only with MFA, and only within their role", async () => {
    const w = await world();
    const {uid} = await create(w, "owner-1");
    await rejectsWith(w.run(specs.adminGetDashboardSpec, uid, {}, {mfa: false}), "mfa_required");
    await w.run(specs.adminGetDashboardSpec, uid);
    await rejectsWith(w.run(specs.adminListStaffSpec, uid), "permission_denied");
  });

  it("a retried create replays instead of failing or duplicating", async () => {
    const w = await world();
    const idem = key("retry");
    const first = await create(w, "owner-1", {idempotencyKey: idem});
    const again = await create(w, "owner-1", {idempotencyKey: idem});
    assert.equal(again.uid, first.uid);
    assert.equal(again.replay, true);
    assert.equal(eventsFor(w, "ADMIN_CREATED").length, 1);
    assert.equal(w.auth.calls.filter(([op]) => op === "createUser").length, 1);
    await rejectsWith(create(w, "owner-1"), "staff_already_exists");
  });

  it("a member's app account cannot become a staff account", async () => {
    const w = await world();
    await rejectsWith(create(w, "owner-1", {email: "member-1@example.com"}), "staff_account_is_member");
    assert.equal(w.db.read("adminStaff/member-1"), undefined);
  });

  it("an existing non-member login is reused without creating another", async () => {
    const w = await world();
    w.auth.addUser("work-login", {email: "worker@mevora.test"});
    const result = await create(w, "owner-1", {email: "worker@mevora.test", role: "support_agent"});
    assert.equal(result.uid, "work-login");
    assert.equal(result.accountCreated, false);
    assert.equal(w.auth.calls.some(([op]) => op === "createUser"), false);
  });

  it("rejects malformed input before touching Auth", async () => {
    const w = await world();
    await rejectsWith(create(w, "owner-1", {email: "not an email"}), "invalid_argument");
    await rejectsWith(create(w, "owner-1", {displayName: ""}), "invalid_argument");
    await rejectsWith(create(w, "owner-1", {idempotencyKey: undefined}), "invalid_argument");
    assert.equal(w.auth.calls.some(([op]) => op === "createUser"), false);
  });

  it("S9 a Trust & Safety admin cannot add staff", async () => {
    const w = await world();
    await rejectsWith(create(w, "tsa-1", {role: "support_agent"}), "permission_denied");
    assert.equal(w.auth.calls.some(([op]) => op === "createUser"), false);
  });

  it("activation email is authorised and audited without exposing a link", async () => {
    const w = await world();
    const {uid} = await create(w, "owner-1");
    const result = await w.run(specs.adminIssueStaffActivationSpec, "owner-1", {targetUid: uid});
    assert.deepEqual(Object.keys(result).sort(), ["email", "uid"]);
    assert.equal(eventsFor(w, "ADMIN_ACTIVATION_ISSUED").length, 1);
    await rejectsWith(w.run(specs.adminIssueStaffActivationSpec, "tsa-1", {targetUid: uid}), "permission_denied");
    await w.run(specs.adminDisableStaffSpec, "owner-1", {targetUid: uid, reason: "left"});
    await rejectsWith(w.run(specs.adminIssueStaffActivationSpec, "owner-1", {targetUid: uid}), "invalid_state_transition");
  });
});

describe("staff control", () => {
  it("S1 the owner sees every staff member with role, status, owner flag and sign-in facts", async () => {
    const w = await world();
    await w.run(specs.adminRecordLoginSpec, "tsa-1");
    await w.run(specs.adminDisableStaffSpec, "owner-1", {targetUid: "support-1", reason: "left"});
    const list = await w.run(specs.adminListStaffSpec, "owner-1");
    assert.deepEqual(list.items.map((i) => i.uid).sort(), ["mod-1", "owner-1", "senior-1", "support-1", "tsa-1"]);
    assert.equal(list.items.find((i) => i.uid === "owner-1").isOwner, true);
    const tsa = list.items.find((i) => i.uid === "tsa-1");
    assert.equal(tsa.lastLoginAt, new Date(T0).toISOString());
    assert.equal(tsa.lastLoginMfa, true);
    assert.equal(list.items.find((i) => i.uid === "support-1").status, "disabled");
    assert.deepEqual(list.summary, {active: 4, disabled: 1});
  });

  it("S10 a Trust & Safety admin cannot list, change, disable or sign out staff", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminListStaffSpec, "tsa-1"), "permission_denied");
    await rejectsWith(w.run(specs.adminGetStaffSpec, "tsa-1", {targetUid: "mod-1"}), "permission_denied");
    await rejectsWith(w.run(specs.adminUpdateStaffRoleSpec, "tsa-1", {targetUid: "mod-1", role: "senior_moderator"}), "permission_denied");
    await rejectsWith(w.run(specs.adminDisableStaffSpec, "tsa-1", {targetUid: "mod-1", reason: "x"}), "permission_denied");
    await rejectsWith(w.run(specs.adminRevokeStaffSessionsSpec, "tsa-1", {targetUid: "mod-1", reason: "x"}), "permission_denied");
  });

  it("S12 the owner changes a role; the old session stops working", async () => {
    const w = await world();
    const loginTime = w.now;
    w.advance(60_000);
    const result = await w.run(specs.adminUpdateStaffRoleSpec, "owner-1", {targetUid: "mod-1", role: "senior_moderator"});
    assert.equal(result.previousRole, "moderator");
    const staff = w.db.read("adminStaff/mod-1");
    assert.equal(staff.role, "senior_moderator");
    assert.equal(staff.lastRoleChangeBy, "owner-1");
    await rejectsWith(w.run(specs.adminGetDashboardSpec, "mod-1", {}, {authTimeMs: loginTime}), "session_revoked");
    await w.run(specs.adminGetDashboardSpec, "mod-1", {}, {authTimeMs: w.now + 1000});
  });

  it("S13/S14 a disabled colleague loses access on the very next request", async () => {
    const w = await world();
    await w.run(specs.adminGetDashboardSpec, "tsa-1");
    await w.run(specs.adminDisableStaffSpec, "owner-1", {targetUid: "tsa-1", reason: "left the company"});
    await rejectsWith(w.run(specs.adminGetDashboardSpec, "tsa-1", {}, {authTimeMs: w.now + 1000}), "staff_inactive");
    assert.deepEqual(w.auth.users.get("tsa-1").customClaims, {});
    assert.ok(w.auth.calls.some(([op, uid]) => op === "revokeRefreshTokens" && uid === "tsa-1"));
    await w.run(specs.adminEnableStaffSpec, "owner-1", {targetUid: "tsa-1", reason: "returned"});
    await w.run(specs.adminGetDashboardSpec, "tsa-1", {}, {authTimeMs: w.now + 1000});
  });

  it("S15 revoking sessions forces a fresh sign-in", async () => {
    const w = await world();
    const loginTime = w.now;
    w.advance(60_000);
    await w.run(specs.adminRevokeStaffSessionsSpec, "owner-1", {targetUid: "senior-1", reason: "lost laptop"});
    await rejectsWith(w.run(specs.adminGetDashboardSpec, "senior-1", {}, {authTimeMs: loginTime}), "session_revoked");
    assert.ok(w.auth.calls.some(([op, uid]) => op === "revokeRefreshTokens" && uid === "senior-1"));
    await w.run(specs.adminGetDashboardSpec, "senior-1", {}, {authTimeMs: w.now + 1000});
    assert.equal(w.db.read("adminStaff/senior-1").status, "active", "revoking is not disabling");
  });

  it("S16 every staff change is in the audit log with actor, target and request", async () => {
    const w = await world();
    const {uid} = await create(w, "owner-1");
    await w.run(specs.adminIssueStaffActivationSpec, "owner-1", {targetUid: uid});
    await w.run(specs.adminUpdateStaffRoleSpec, "owner-1", {targetUid: uid, role: "senior_moderator"});
    await w.run(specs.adminRevokeStaffSessionsSpec, "owner-1", {targetUid: uid, reason: "rotate"});
    await w.run(specs.adminDisableStaffSpec, "owner-1", {targetUid: uid, reason: "left"});
    await w.run(specs.adminEnableStaffSpec, "owner-1", {targetUid: uid, reason: "back"});
    const trail = events(w).filter((e) => e.targetId === uid).map((e) => e.action).sort();
    assert.deepEqual(trail, [
      "ADMIN_ACTIVATION_ISSUED",
      "ADMIN_CREATED",
      "ADMIN_DISABLED",
      "ADMIN_ENABLED",
      "ADMIN_ROLE_CHANGED",
      "ADMIN_SESSIONS_REVOKED",
    ]);
    for (const e of events(w).filter((x) => x.targetId === uid)) {
      assert.equal(e.actorAdminId, "owner-1");
      assert.equal(e.actorRole, "super_admin");
      assert.equal(e.targetType, "staff");
      assert.ok(e.requestId);
    }
  });

  it("staff detail shows account facts and a bounded activity summary", async () => {
    const w = await world();
    await w.run(specs.adminSuspendUserSpec, "tsa-1", {uid: "member-1", reasonCode: "SPAM", durationHours: 24, internalNote: "x", idempotencyKey: key()});
    await w.run(specs.adminBanUserSpec, "tsa-1", {uid: "member-1", reasonCode: "SPAM", internalNote: "x", idempotencyKey: key()});
    await w.run(specs.adminRestoreUserSpec, "tsa-1", {uid: "member-1", reasonCode: "ERROR_CORRECTION", internalNote: "x", idempotencyKey: key()});
    w.auth.users.get("tsa-1").multiFactor = {enrolledFactors: [{factorId: "totp", secret: "never-shown"}]};
    const detail = await w.run(specs.adminGetStaffSpec, "owner-1", {targetUid: "tsa-1"});
    assert.equal(detail.staff.role, "trust_safety_admin");
    assert.deepEqual(detail.account.mfaFactors, ["totp"]);
    assert.equal(JSON.stringify(detail).includes("never-shown"), false);
    assert.equal(detail.activity.usersSuspended, 1);
    assert.equal(detail.activity.usersBanned, 1);
    assert.equal(detail.activity.usersRestored, 1);
    assert.equal(detail.activity.appealsResolved, 0);
    assert.deepEqual(detail.recentActions.map((a) => a.action).sort(), ["USER_BANNED", "USER_RESTORED", "USER_SUSPENDED"]);
    assert.ok(detail.lastActivityAt);
    await rejectsWith(w.run(specs.adminGetStaffSpec, "owner-1", {targetUid: "nobody"}), "not_found");
  });
});

describe("Trust & Safety admin is the operational admin", () => {
  it("S5/S6/S7/S8 moderates, bans, restores, answers support and reads the audit log", async () => {
    const w = await world();
    await w.run(specs.adminWarnUserSpec, "tsa-1", {uid: "member-1", reasonCode: "SPAM", idempotencyKey: key()});
    await w.run(specs.adminBanUserSpec, "tsa-1", {uid: "member-1", reasonCode: "SPAM", internalNote: "x", idempotencyKey: key()});
    await w.run(specs.adminRestoreUserSpec, "tsa-1", {uid: "member-1", reasonCode: "ERROR_CORRECTION", internalNote: "x", idempotencyKey: key()});
    await w.db.doc("supportTickets/t1").set({userId: "member-1", subject: "Help", message: "m", status: "open", attachments: [], createdAt: new Date(w.now), updatedAt: new Date(w.now)});
    await w.run(specs.adminReplySupportTicketSpec, "tsa-1", {ticketId: "t1", text: "We are on it", idempotencyKey: key()});
    const audit = await w.run(specs.adminListAuditEventsSpec, "tsa-1", {actorAdminId: "tsa-1"});
    assert.ok(audit.items.length >= 4);
  });

  it("does not hold owner-level permissions", async () => {
    const {ROLE_PERMISSIONS} = require("../lib/admin/auth/roles.js");
    for (const p of ["admin.manage_staff", "admin.manage_roles", "admin.maintenance"]) {
      assert.equal(ROLE_PERMISSIONS.trust_safety_admin.has(p), false, p);
      assert.equal(ROLE_PERMISSIONS.super_admin.has(p), true, p);
    }
  });
});

describe("owner dashboard", () => {
  it("adds platform and staff counters only for the permissions that allow them", async () => {
    const w = await world();
    await w.addMember("member-2", {account: {accountStatus: "suspended", lastActiveAt: new Date(w.now - 1000)}});
    await w.addMember("member-3", {account: {accountStatus: "banned", createdAt: new Date(w.now - 30 * 86400000)}});
    await w.run(specs.adminDisableStaffSpec, "owner-1", {targetUid: "support-1", reason: "left"});
    const owner = await w.run(specs.adminGetDashboardSpec, "owner-1");
    assert.equal(owner.counters.totalUsers, 3);
    assert.equal(owner.counters.newUsers7d, 2);
    assert.equal(owner.counters.activeUsers7d, 1);
    assert.equal(owner.counters.suspendedAccounts, 1);
    assert.equal(owner.counters.bannedAccounts, 1);
    assert.equal(owner.counters.activeStaff, 4);
    assert.equal(owner.counters.disabledStaff, 1);
    assert.ok(owner.recentAdminActions.some((a) => a.action === "ADMIN_DISABLED"));
    assert.equal(owner.recentAdminActions.some((a) => a.action === "ADMIN_LOGIN"), false);

    const tsa = await w.run(specs.adminGetDashboardSpec, "tsa-1");
    assert.equal(tsa.counters.totalUsers, 3);
    assert.equal("activeStaff" in tsa.counters, false);

    const support = await w.run(specs.adminGetDashboardSpec, "mod-1");
    assert.deepEqual(support.recentAdminActions, [], "no audit.read, no staff activity feed");
  });
});

describe("audit oversight filters", () => {
  async function busyWorld() {
    const w = await world();
    await w.run(specs.adminSuspendUserSpec, "tsa-1", {uid: "member-1", reasonCode: "SPAM", durationHours: 24, internalNote: "x", idempotencyKey: key()});
    w.advance(1000);
    await w.run(specs.adminRestoreUserSpec, "senior-1", {uid: "member-1", reasonCode: "ERROR_CORRECTION", internalNote: "x", idempotencyKey: key()});
    w.advance(1000);
    await w.run(specs.adminBanUserSpec, "tsa-1", {uid: "member-1", reasonCode: "SPAM", internalNote: "x", idempotencyKey: key()});
    w.advance(1000);
    await w.run(specs.adminDisableStaffSpec, "owner-1", {targetUid: "mod-1", reason: "left"});
    return w;
  }

  it("answers 'who banned whom' with combined filters", async () => {
    const w = await busyWorld();
    const bans = await w.run(specs.adminListAuditEventsSpec, "owner-1", {action: "USER_BANNED", targetId: "member-1"});
    assert.deepEqual(bans.items.map((e) => e.actorAdminId), ["tsa-1"]);
    const byTsa = await w.run(specs.adminListAuditEventsSpec, "owner-1", {actorAdminId: "tsa-1", targetType: "user"});
    assert.deepEqual(byTsa.items.map((e) => e.action), ["USER_BANNED", "USER_SUSPENDED"]);
    const staffChanges = await w.run(specs.adminListAuditEventsSpec, "owner-1", {targetType: "staff", actorRole: "super_admin"});
    assert.deepEqual(staffChanges.items.map((e) => e.action), ["ADMIN_DISABLED"]);
  });

  it("filters by date range (inclusive day bounds, UTC)", async () => {
    const w = await busyWorld();
    // serverTimestamp() in the fake uses the wall clock, so take the day from the log itself.
    const today = (await w.run(specs.adminListAuditEventsSpec, "owner-1", {})).items[0].createdAt.slice(0, 10);
    const all = await w.run(specs.adminListAuditEventsSpec, "owner-1", {from: today, to: today});
    assert.equal(all.items.length, 4);
    const none = await w.run(specs.adminListAuditEventsSpec, "owner-1", {from: "2026-01-01", to: "2026-01-02"});
    assert.equal(none.items.length, 0);
    await rejectsWith(w.run(specs.adminListAuditEventsSpec, "owner-1", {from: "2026-10-02", to: "2026-10-01"}), "invalid_argument");
    await rejectsWith(w.run(specs.adminListAuditEventsSpec, "owner-1", {from: "yesterday"}), "invalid_argument");
  });

  it("pages through filtered results without skipping or repeating", async () => {
    const w = await busyWorld();
    const first = await w.run(specs.adminListAuditEventsSpec, "owner-1", {targetId: "member-1", limit: 2});
    assert.equal(first.items.length, 2);
    assert.ok(first.nextCursor);
    const second = await w.run(specs.adminListAuditEventsSpec, "owner-1", {targetId: "member-1", limit: 2, cursor: first.nextCursor});
    const ids = [...first.items, ...second.items].map((e) => e.eventId);
    assert.equal(new Set(ids).size, ids.length);
    assert.equal(ids.length, 3);
  });

  it("bounds the number of documents one request reads", async () => {
    const w = await world();
    const {appendAuditEvent} = require("../lib/admin/audit/auditService.js");
    for (let i = 0; i < AUDIT_SCAN_CAP + 50; i += 1) {
      const batch = w.db.batch();
      appendAuditEvent(batch, w.db, {actorAdminId: "mod-1", actorRole: "moderator", action: "CASE_NOTE_ADDED", targetType: "case", targetId: `c${i}`}, w.now + i);
      await batch.commit();
    }
    const page = await w.run(specs.adminListAuditEventsSpec, "owner-1", {actorAdminId: "mod-1", action: "USER_BANNED"});
    assert.equal(page.items.length, 0);
    assert.equal(page.scanned, AUDIT_SCAN_CAP);
    assert.equal(page.partial, true);
    assert.ok(page.nextCursor, "the scan can be continued");
  });

  it("is audit.read only", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminListAuditEventsSpec, "mod-1", {}), "permission_denied");
    await w.run(specs.adminListAuditEventsSpec, "tsa-1", {});
  });
});
