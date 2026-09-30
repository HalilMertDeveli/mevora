const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {createAdminWorld, rejectsWith, key} = require("./helpers/adminHarness.cjs");
const specs = require("../lib/admin/commands.js");
const {
  ROLE_PERMISSIONS,
  ADMIN_ROLES,
  canGrantRole,
} = require("../lib/admin/auth/roles.js");
const {PERMISSIONS} = require("../lib/admin/auth/permissions.js");
const {
  authorizeAdminRequest,
  bffCredentialValid,
  tokenHasSecondFactor,
} = require("../lib/admin/auth/adminAuthorization.js");
const {resolveAdminAuthEnv} = require("../lib/admin/command.js");

async function world() {
  const w = createAdminWorld();
  await w.addStaff("support-1", "support_agent");
  await w.addStaff("mod-1", "moderator");
  await w.addStaff("senior-1", "senior_moderator");
  await w.addStaff("tsa-1", "trust_safety_admin");
  await w.addStaff("super-1", "super_admin");
  await w.addStaff("super-2", "super_admin");
  await w.addMember("member-1");
  await w.addMember("member-2");
  return w;
}

const suspend = (uid) => ({uid, reasonCode: "HARASSMENT", durationHours: 24, internalNote: "repeat abuse", idempotencyKey: key("s")});
const ban = (uid) => ({uid, reasonCode: "SCAM_FRAUD", internalNote: "confirmed scam", idempotencyKey: key("b")});

describe("RBAC — role → permission map is the single authority", () => {
  it("every role maps only to known permissions", () => {
    for (const role of ADMIN_ROLES) {
      for (const permission of ROLE_PERMISSIONS[role]) {
        assert.ok(PERMISSIONS.includes(permission), `${role} → unknown ${permission}`);
      }
    }
  });

  it("support agents handle support but cannot sanction", () => {
    const p = ROLE_PERMISSIONS.support_agent;
    assert.ok(p.has("support.reply") && p.has("support.resolve"));
    for (const denied of ["user.suspend", "user.ban", "user.warn", "photo.reject", "user.read_sensitive", "audit.read"]) {
      assert.equal(p.has(denied), false, denied);
    }
  });

  it("moderators may suspend but never permanently ban", () => {
    const p = ROLE_PERMISSIONS.moderator;
    assert.ok(p.has("user.suspend") && p.has("user.warn"));
    assert.equal(p.has("user.ban"), false);
    assert.equal(p.has("user.restore"), false);
  });

  it("senior moderators add ban, restore and appeal decisions", () => {
    const p = ROLE_PERMISSIONS.senior_moderator;
    for (const granted of ["user.ban", "user.restore", "appeal.resolve"]) {
      assert.ok(p.has(granted), granted);
    }
    assert.equal(p.has("admin.manage_roles"), false);
  });

  it("only super admins manage roles", () => {
    for (const role of ADMIN_ROLES) {
      assert.equal(ROLE_PERMISSIONS[role].has("admin.manage_roles"), role === "super_admin", role);
    }
  });

  it("no role can grant a role at or above its own, except super admin", () => {
    assert.equal(canGrantRole("trust_safety_admin", "trust_safety_admin"), false);
    assert.equal(canGrantRole("trust_safety_admin", "senior_moderator"), true);
    assert.equal(canGrantRole("super_admin", "super_admin"), true);
  });
});

describe("authorization chain", () => {
  it("a normal member (no admin claim) is denied", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminGetDashboardSpec, "member-1", {}, {admin: false}), "permission_denied");
  });

  it("an unauthenticated request is denied", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminGetDashboardSpec, null), "unauthenticated");
  });

  it("a request that did not come through the admin web's server is denied", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminGetDashboardSpec, "super-1", {}, {bff: false}), "permission_denied");
    await rejectsWith(w.run(specs.adminGetDashboardSpec, "super-1", {}, {bffValue: "wrong-secret-value!"}), "permission_denied");
  });

  it("an unset BFF secret fails closed", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminGetDashboardSpec, "super-1", {}, {env: {bffSecret: ""}, bffValue: ""}), "permission_denied");
    assert.equal(bffCredentialValid("", ""), false);
  });

  it("a staff token without a second factor is refused in production", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminGetDashboardSpec, "super-1", {}, {mfa: false}), "mfa_required");
  });

  it("the emulator-only MFA relaxation lets the same token through", async () => {
    const w = await world();
    const result = await w.run(specs.adminGetDashboardSpec, "super-1", {}, {mfa: false, env: {allowMissingMfa: true}});
    assert.ok(result.counters);
  });

  it("production never relaxes MFA, whatever the environment variable says", () => {
    const saved = {emu: process.env.FUNCTIONS_EMULATOR, mfa: process.env.ADMIN_EMULATOR_REQUIRE_MFA};
    try {
      delete process.env.FUNCTIONS_EMULATOR;
      process.env.ADMIN_EMULATOR_REQUIRE_MFA = "false";
      const env = resolveAdminAuthEnv();
      assert.equal(env.allowMissingMfa, false);
      assert.equal(env.bffSecret, "", "no dev secret outside the emulator");
    } finally {
      if (saved.emu === undefined) delete process.env.FUNCTIONS_EMULATOR; else process.env.FUNCTIONS_EMULATOR = saved.emu;
      if (saved.mfa === undefined) delete process.env.ADMIN_EMULATOR_REQUIRE_MFA; else process.env.ADMIN_EMULATOR_REQUIRE_MFA = saved.mfa;
    }
  });

  it("recognises a completed second factor on the token", () => {
    assert.equal(tokenHasSecondFactor({firebase: {sign_in_second_factor: "totp"}}), true);
    assert.equal(tokenHasSecondFactor({firebase: {}}), false);
  });

  it("a disabled staff member is denied even with a valid admin token", async () => {
    const w = await world();
    await w.db.doc("adminStaff/mod-1").set({status: "disabled"}, {merge: true});
    await rejectsWith(w.run(specs.adminGetDashboardSpec, "mod-1"), "staff_inactive");
  });

  it("an admin claim with no adminStaff record is denied", async () => {
    const w = await world();
    w.auth.addUser("ghost", {customClaims: {admin: true, adminRole: "super_admin"}});
    await rejectsWith(w.run(specs.adminGetDashboardSpec, "ghost"), "staff_inactive");
  });

  it("tokens issued before a revocation are refused", async () => {
    const w = await world();
    await w.db.doc("adminStaff/mod-1").set({sessionsValidAfter: new Date(w.now + 60_000)}, {merge: true});
    await rejectsWith(w.run(specs.adminGetDashboardSpec, "mod-1"), "session_revoked");
  });

  it("support agent cannot suspend", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminSuspendUserSpec, "support-1", suspend("member-1")), "permission_denied");
  });

  it("moderator can suspend", async () => {
    const w = await world();
    const result = await w.run(specs.adminSuspendUserSpec, "mod-1", suspend("member-1"));
    assert.equal(result.type, "TEMPORARY_SUSPENSION");
  });

  it("moderator cannot permanently ban", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminBanUserSpec, "mod-1", ban("member-1")), "permission_denied");
    assert.equal(w.db.read("users/member-1").accountStatus, "active");
  });

  it("senior moderator can ban", async () => {
    const w = await world();
    const result = await w.run(specs.adminBanUserSpec, "senior-1", ban("member-1"));
    assert.equal(result.accountStatus, "banned");
  });

  it("super admin can manage roles", async () => {
    const w = await world();
    w.auth.addUser("new-staff", {email: "new-staff@mevora.test"});
    const result = await w.run(specs.adminUpdateStaffRoleSpec, "super-1", {targetUid: "new-staff", role: "moderator"});
    assert.equal(result.role, "moderator");
    assert.equal(w.db.read("adminStaff/new-staff").role, "moderator");
    assert.deepEqual(w.auth.users.get("new-staff").customClaims, {admin: true, adminRole: "moderator"});
  });

  it("a client-supplied role is ignored — the staff record decides", async () => {
    const w = await world();
    // Token claims super_admin; the staff record says moderator.
    await rejectsWith(
      w.run(specs.adminBanUserSpec, "mod-1", {...ban("member-1"), role: "super_admin"}, {token: {adminRole: "super_admin", role: "super_admin"}}),
      "permission_denied",
    );
  });

  it("the actor's permissions come from roles.ts, not the token", async () => {
    const w = await world();
    const actor = await authorizeAdminRequest(
      w.request("mod-1", {}, {token: {permissions: ["admin.manage_roles"]}}),
      "dashboard.read",
      w.deps,
      w.env,
    );
    assert.equal(actor.role, "moderator");
    assert.equal(actor.permissions.has("admin.manage_roles"), false);
  });

  it("staff management guards: self, rank, and the last super admin", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminUpdateStaffRoleSpec, "super-1", {targetUid: "super-1", role: "moderator"}), "cannot_modify_self");
    await rejectsWith(w.run(specs.adminDisableStaffSpec, "super-1", {targetUid: "super-1", reason: "x"}), "cannot_modify_self");
    await w.run(specs.adminDisableStaffSpec, "super-1", {targetUid: "super-2", reason: "left the company"});
    assert.equal(w.db.read("adminStaff/super-2").status, "disabled");
    assert.deepEqual(w.auth.users.get("super-2").customClaims, {});
    assert.ok(w.auth.calls.some(([op, uid]) => op === "revokeRefreshTokens" && uid === "super-2"));
    // super-1 is now the only active super admin: another super admin cannot
    // exist to demote them, and nobody lower can touch them.
    await w.addStaff("tsa-2", "trust_safety_admin");
    await rejectsWith(w.run(specs.adminDisableStaffSpec, "tsa-1", {targetUid: "super-1", reason: "x"}), "permission_denied");
  });

  it("the last active super admin can be neither demoted nor disabled", async () => {
    // Through the command surface this is unreachable (an acting super admin
    // is itself active, and nobody may act on themselves), so the guard is
    // exercised directly: e.g. a bootstrap tool acting with no staff record.
    const {setStaffStatus, updateStaffRole} = require("../lib/admin/staff/staffService.js");
    const {permissionsForRole} = require("../lib/admin/auth/roles.js");
    const w = createAdminWorld();
    await w.addStaff("only-super", "super_admin");
    const outsider = {uid: "bootstrap", role: "super_admin", permissions: permissionsForRole("super_admin"), displayName: null, mfa: true};
    await rejectsWith(setStaffStatus(w.deps, outsider, {targetUid: "only-super", status: "disabled", reason: "x"}, "req-1"), "last_super_admin");
    await rejectsWith(updateStaffRole(w.deps, outsider, {targetUid: "only-super", email: null, role: "moderator", displayName: null}, "req-2"), "last_super_admin");
    assert.equal(w.db.read("adminStaff/only-super").status, "active");
    assert.equal(w.db.read("adminStaff/only-super").role, "super_admin");
  });

  it("role grants never exceed the grantor's rank", async () => {
    const w = await world();
    w.auth.addUser("candidate", {});
    // tsa lacks admin.manage_roles entirely.
    await rejectsWith(w.run(specs.adminUpdateStaffRoleSpec, "tsa-1", {targetUid: "candidate", role: "moderator"}), "permission_denied");
  });

  it("rate limits apply per staff member", async () => {
    const w = await world();
    for (let i = 0; i < 30; i += 1) {
      await w.run(specs.adminSearchUsersSpec, "mod-1", {query: "member"});
    }
    await rejectsWith(w.run(specs.adminSearchUsersSpec, "mod-1", {query: "member"}), "rate_limited");
    // Another staff member has their own budget.
    await w.run(specs.adminSearchUsersSpec, "senior-1", {query: "member"});
  });

  it("malformed input is a domain error, not a crash", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminSuspendUserSpec, "mod-1", {uid: "member-1", reasonCode: "NOT_A_CODE", durationHours: 24, internalNote: "x", idempotencyKey: key()}), "invalid_argument");
    await rejectsWith(w.run(specs.adminSuspendUserSpec, "mod-1", {uid: "member-1", reasonCode: "SPAM", durationHours: -5, internalNote: "x", idempotencyKey: key()}), "invalid_argument");
    await rejectsWith(w.run(specs.adminSuspendUserSpec, "mod-1", {uid: "member-1", reasonCode: "SPAM", durationHours: 24 * 400, internalNote: "x", idempotencyKey: key()}), "invalid_argument");
    await rejectsWith(w.run(specs.adminSuspendUserSpec, "mod-1", {uid: "member-1", reasonCode: "SPAM", durationHours: 24, idempotencyKey: key()}), "invalid_argument");
    await rejectsWith(w.run(specs.adminSuspendUserSpec, "mod-1", {uid: "a/b", reasonCode: "SPAM", durationHours: 24, internalNote: "x", idempotencyKey: key()}), "invalid_argument");
  });
});
