import {randomBytes} from "node:crypto";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {AUDIT_COLLECTION, appendAuditEvent} from "../audit/auditService.js";
import type {AuditAction} from "../audit/auditTypes.js";
import {STAFF_COLLECTION, parseStaffRecord, type AdminActor, type StaffRecord} from "../auth/adminAuthorization.js";
import {
  ROLE_RANK,
  canGrantRole,
  canManageStaffMember,
  permissionsForRole,
  type AdminRole,
  type GrantableRole,
} from "../auth/roles.js";
import type {AdminDeps} from "../deps.js";
import {AdminError} from "../errors.js";
import {deterministicId, iso} from "../validation.js";

/**
 * Staff management: `adminStaff/{uid}` plus the `admin` / `adminRole` custom
 * claims that mirror it.
 *
 * The staff document is the authority (authorizeAdminRequest reads it on
 * every request); the claims are a coarse, cacheable hint. Disabling a staff
 * member therefore takes effect on their very next request, and their
 * refresh tokens are revoked so the session cannot be renewed either.
 *
 * Guards: nobody changes their own role, disables themselves or revokes their
 * own sessions; super_admin is never granted through the console; roles can
 * only be granted below one's own rank (super admins excepted); the owner's
 * record is untouchable here; the last active super admin can be neither
 * demoted nor disabled.
 */

export const PERMISSIONS_VERSION = 1;

/** Audit actions summarised on a staff member's page, grouped by what they mean. */
export const STAFF_ACTIVITY_GROUPS: Readonly<Record<string, readonly AuditAction[]>> = {
  casesResolved: ["CASE_RESOLVED"],
  reportsResolved: ["REPORT_RESOLVED"],
  photosReviewed: ["PHOTO_APPROVED", "PHOTO_REJECTED", "PHOTO_REMOVED"],
  usersWarned: ["USER_WARNED"],
  usersSuspended: ["USER_SUSPENDED"],
  usersBanned: ["USER_BANNED"],
  usersRestored: ["USER_RESTORED"],
  supportReplies: ["SUPPORT_REPLIED"],
  supportResolved: ["SUPPORT_RESOLVED"],
  appealsResolved: ["APPEAL_ACCEPTED", "APPEAL_REJECTED"],
  verificationActions: ["VERIFICATION_REVERIFICATION_REQUIRED", "VERIFICATION_ESCALATED"],
};

const RECENT_ACTIVITY_LIMIT = 20;

export async function getMyStaffProfile(deps: AdminDeps, actor: AdminActor) {
  return {
    uid: actor.uid,
    role: actor.role,
    displayName: actor.displayName,
    permissions: [...actor.permissions].sort(),
    mfa: actor.mfa,
    isOwner: actor.isOwner,
    permissionsVersion: PERMISSIONS_VERSION,
    serverTime: new Date(deps.now()).toISOString(),
  };
}

export async function recordAdminLogin(deps: AdminDeps, actor: AdminActor, requestId: string) {
  const nowMs = deps.now();
  const batch = deps.db.batch();
  // Server-owned sign-in stamp for the staff list; the audit event is the record.
  batch.set(deps.db.doc(`${STAFF_COLLECTION}/${actor.uid}`), {
    lastLoginAt: Timestamp.fromMillis(nowMs),
    lastLoginMfa: actor.mfa,
  }, {merge: true});
  appendAuditEvent(batch, deps.db, {
    actorAdminId: actor.uid,
    actorRole: actor.role,
    action: "ADMIN_LOGIN",
    targetType: "staff",
    targetId: actor.uid,
    requestId,
    metadata: {mfa: actor.mfa},
  }, nowMs);
  await batch.commit();
  return getMyStaffProfile(deps, actor);
}

function staffRow(doc: FirebaseFirestore.DocumentSnapshot) {
  const record = parseStaffRecord(doc.id, doc.data());
  return {
    uid: doc.id,
    role: record?.role ?? doc.get("role") ?? null,
    status: record?.status ?? "disabled",
    isOwner: record?.isOwner ?? false,
    displayName: record?.displayName ?? null,
    email: record?.email ?? null,
    createdAt: iso(doc.get("createdAt")),
    createdBy: doc.get("createdBy") ?? null,
    updatedAt: iso(doc.get("updatedAt")),
    lastRoleChangeBy: doc.get("lastRoleChangeBy") ?? null,
    lastRoleChangeAt: iso(doc.get("lastRoleChangeAt")),
    lastLoginAt: iso(doc.get("lastLoginAt")),
    lastLoginMfa: typeof doc.get("lastLoginMfa") === "boolean" ? doc.get("lastLoginMfa") : null,
    statusReason: typeof doc.get("statusReason") === "string" ? doc.get("statusReason") : null,
    // Test identities from tool/seedEmulatorAdminQa.cjs, badged in the console.
    qaSeed: doc.get("seededFor") === "emulator-qa",
  };
}

export async function listStaff(deps: AdminDeps) {
  const snap = await deps.db.collection(STAFF_COLLECTION).orderBy("createdAt", "asc").limit(200).get();
  const items = snap.docs.map(staffRow);
  return {
    items,
    summary: {
      active: items.filter((i) => i.status === "active").length,
      disabled: items.filter((i) => i.status !== "active").length,
    },
  };
}

async function countActiveSuperAdmins(tx: FirebaseFirestore.Transaction, deps: AdminDeps): Promise<number> {
  const snap = await tx.get(
    deps.db.collection(STAFF_COLLECTION)
      .where("role", "==", "super_admin")
      .where("status", "==", "active")
      .limit(10),
  );
  return snap.size;
}

async function mirrorClaims(deps: AdminDeps, uid: string, role: AdminRole | null): Promise<void> {
  const user = await deps.auth.getUser(uid);
  const claims = {...(user.customClaims ?? {})};
  if (role) {
    claims.admin = true;
    claims.adminRole = role;
  } else {
    delete claims.admin;
    delete claims.adminRole;
  }
  await deps.auth.setCustomUserClaims(uid, claims);
}

/** The owner's record is never changed by a console command, whoever asks. */
function assertNotOwner(current: StaffRecord | null): void {
  if (current?.isOwner) {
    throw new AdminError("cannot_modify_owner");
  }
}

function assertCanManage(actor: AdminActor, current: StaffRecord): void {
  assertNotOwner(current);
  if (!canManageStaffMember(actor.role, current.role)) {
    throw new AdminError(current.role === "super_admin" ? "cannot_modify_super_admin" : "cannot_modify_staff");
  }
}

function normalizeEmail(email: string): string {
  const value = email.trim().toLowerCase();
  // Deliberately loose: Firebase Auth is the real validator. This only keeps
  // obvious garbage (and whitespace tricks) out of an audited record.
  if (!/^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,63}$/.test(value)) {
    throw new AdminError("invalid_argument", "email");
  }
  return value;
}

/**
 * Adds a colleague to the console.
 *
 * Creates the Firebase Auth login when none exists, with a random password
 * nobody ever sees; the admin web then asks Firebase to email a password-setup
 * link to that address, so the super admin never learns the credential. An
 * existing login is reused only when it is not a Mevora member account: staff
 * accounts are dedicated work identities. MFA enrolment is forced at first
 * console sign-in (adminRecordLogin → mfa_required).
 *
 * Retry-safe: the same idempotency key replays the first result.
 */
export async function createStaff(
  deps: AdminDeps,
  actor: AdminActor,
  input: {email: string; displayName: string; role: GrantableRole; idempotencyKey: string},
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  const email = normalizeEmail(input.email);
  if (!canGrantRole(actor.role, input.role)) {
    throw new AdminError("role_grant_forbidden");
  }
  const createKey = deterministicId("staffcreate", actor.uid, email, input.idempotencyKey);

  let uid: string;
  let accountCreated = false;
  try {
    uid = (await deps.auth.getUserByEmail(email)).uid;
  } catch {
    uid = (await deps.auth.createUser({
      email,
      displayName: input.displayName,
      password: randomBytes(32).toString("base64url"),
      // Possession of the inbox is proven by the password-setup link, the
      // only way into this account; Firebase requires a verified address
      // before a second factor can be enrolled.
      emailVerified: true,
      disabled: false,
    })).uid;
    accountCreated = true;
  }
  if (uid === actor.uid) {
    throw new AdminError("cannot_modify_self");
  }

  const ref = db.doc(`${STAFF_COLLECTION}/${uid}`);
  const memberRef = db.doc(`users/${uid}`);
  const outcome = await db.runTransaction(async (tx) => {
    const [snap, member] = await Promise.all([tx.get(ref), tx.get(memberRef)]);
    if (snap.exists) {
      if (snap.get("createKey") === createKey) {
        return {replay: true};
      }
      throw new AdminError("staff_already_exists");
    }
    if (member.exists) {
      throw new AdminError("staff_account_is_member");
    }
    tx.set(ref, {
      uid,
      role: input.role,
      status: "active",
      isOwner: false,
      displayName: input.displayName,
      email,
      permissionsVersion: PERMISSIONS_VERSION,
      createdAt: FieldValue.serverTimestamp(),
      createdBy: actor.uid,
      createKey,
      lastRoleChangeBy: actor.uid,
      lastRoleChangeAt: Timestamp.fromMillis(nowMs),
      activationIssuedAt: Timestamp.fromMillis(nowMs),
      sessionsValidAfter: Timestamp.fromMillis(nowMs),
      updatedAt: FieldValue.serverTimestamp(),
    });
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "ADMIN_CREATED",
      targetType: "staff",
      targetId: uid,
      requestId,
      metadata: {role: input.role, accountCreated},
    }, nowMs);
    return {replay: false};
  });
  if (!outcome.replay) {
    await mirrorClaims(deps, uid, input.role);
    await deps.auth.revokeRefreshTokens(uid);
  }
  return {uid, email, role: input.role, accountCreated, replay: outcome.replay};
}

/**
 * Authorises (and audits) sending a password-setup email to a colleague. The
 * admin web performs the send through Firebase Auth; the link never passes
 * through this backend or the super admin's screen.
 */
export async function issueStaffActivation(
  deps: AdminDeps,
  actor: AdminActor,
  input: {targetUid: string},
  requestId: string,
) {
  if (input.targetUid === actor.uid) {
    throw new AdminError("cannot_modify_self");
  }
  const snap = await deps.db.doc(`${STAFF_COLLECTION}/${input.targetUid}`).get();
  const current = parseStaffRecord(input.targetUid, snap.data());
  if (!current) {
    throw new AdminError("not_found", "staff");
  }
  assertCanManage(actor, current);
  if (current.status !== "active") {
    // Not staff_inactive: that code ends the *caller's* console session.
    throw new AdminError("invalid_state_transition", "staff_disabled");
  }
  const authUser = await deps.auth.getUser(input.targetUid).catch(() => null);
  if (!authUser?.email) {
    throw new AdminError("not_found", "auth_user");
  }
  const nowMs = deps.now();
  const batch = deps.db.batch();
  batch.set(snap.ref, {activationIssuedAt: Timestamp.fromMillis(nowMs)}, {merge: true});
  appendAuditEvent(batch, deps.db, {
    actorAdminId: actor.uid,
    actorRole: actor.role,
    action: "ADMIN_ACTIVATION_ISSUED",
    targetType: "staff",
    targetId: input.targetUid,
    requestId,
    metadata: {role: current.role},
  }, nowMs);
  await batch.commit();
  return {uid: input.targetUid, email: authUser.email};
}

/**
 * Changes an existing staff member's role. New colleagues are added with
 * createStaff; this never turns an arbitrary account into staff.
 */
export async function updateStaffRole(
  deps: AdminDeps,
  actor: AdminActor,
  input: {targetUid: string | null; email: string | null; role: AdminRole; displayName: string | null},
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  let targetUid = input.targetUid;
  if (!targetUid && input.email) {
    try {
      targetUid = (await deps.auth.getUserByEmail(input.email.toLowerCase())).uid;
    } catch {
      throw new AdminError("not_found", "auth_user");
    }
  }
  if (!targetUid) {
    throw new AdminError("invalid_argument", "target");
  }
  if (targetUid === actor.uid) {
    throw new AdminError("cannot_modify_self");
  }
  if (!canGrantRole(actor.role, input.role)) {
    throw new AdminError("role_grant_forbidden");
  }
  const ref = db.doc(`${STAFF_COLLECTION}/${targetUid}`);
  const uid = targetUid;
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = parseStaffRecord(uid, snap.data());
    if (!current) {
      throw new AdminError("not_found", "staff");
    }
    const superAdmins = current.role === "super_admin" && input.role !== "super_admin"
      ? await countActiveSuperAdmins(tx, deps)
      : null;
    assertCanManage(actor, current);
    if (superAdmins !== null && current.status === "active" && superAdmins <= 1) {
      throw new AdminError("last_super_admin");
    }
    if (current.role === input.role && current.status === "active") {
      return {changed: false, previousRole: current.role};
    }
    tx.set(ref, {
      role: input.role,
      status: "active",
      displayName: input.displayName ?? current.displayName ?? null,
      permissionsVersion: PERMISSIONS_VERSION,
      lastRoleChangeBy: actor.uid,
      lastRoleChangeAt: Timestamp.fromMillis(nowMs),
      // A role change re-issues the session: tokens minted under the old role
      // are refused from now on.
      sessionsValidAfter: Timestamp.fromMillis(nowMs),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "ADMIN_ROLE_CHANGED",
      targetType: "staff",
      targetId: uid,
      requestId,
      metadata: {previousRole: current.role, previousStatus: current.status, newRole: input.role},
    }, nowMs);
    return {changed: true, previousRole: current.role};
  });
  if (result.changed) {
    await mirrorClaims(deps, uid, input.role);
    await deps.auth.revokeRefreshTokens(uid);
  }
  return {uid, role: input.role, changed: result.changed, previousRole: result.previousRole, permissions: [...permissionsForRole(input.role)].sort()};
}

export async function setStaffStatus(
  deps: AdminDeps,
  actor: AdminActor,
  input: {targetUid: string; status: "active" | "disabled"; reason: string},
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  if (input.targetUid === actor.uid) {
    throw new AdminError("cannot_modify_self");
  }
  const ref = db.doc(`${STAFF_COLLECTION}/${input.targetUid}`);
  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = parseStaffRecord(input.targetUid, snap.data());
    if (!current) {
      throw new AdminError("not_found", "staff");
    }
    const superAdmins = current.role === "super_admin" && input.status === "disabled"
      ? await countActiveSuperAdmins(tx, deps)
      : null;
    assertCanManage(actor, current);
    if (current.status === input.status) {
      return {changed: false, role: current.role};
    }
    if (superAdmins !== null && superAdmins <= 1) {
      throw new AdminError("last_super_admin");
    }
    tx.set(ref, {
      status: input.status,
      statusReason: input.reason,
      sessionsValidAfter: Timestamp.fromMillis(nowMs),
      updatedAt: FieldValue.serverTimestamp(),
      lastRoleChangeBy: actor.uid,
      lastRoleChangeAt: Timestamp.fromMillis(nowMs),
    }, {merge: true});
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: input.status === "disabled" ? "ADMIN_DISABLED" : "ADMIN_ENABLED",
      targetType: "staff",
      targetId: input.targetUid,
      requestId,
      metadata: {role: current.role, reason: input.reason, rankGap: ROLE_RANK[actor.role] - ROLE_RANK[current.role]},
    }, nowMs);
    return {changed: true, role: current.role};
  });
  if (outcome.changed) {
    await mirrorClaims(deps, input.targetUid, input.status === "active" ? outcome.role : null);
    await deps.auth.revokeRefreshTokens(input.targetUid);
  }
  return {uid: input.targetUid, status: input.status, changed: outcome.changed};
}

/**
 * Ends every console session a colleague holds: tokens whose auth_time is
 * before now are refused on the next request (session_revoked) and refresh
 * tokens are revoked, so they must sign in again — with MFA.
 */
export async function revokeStaffSessions(
  deps: AdminDeps,
  actor: AdminActor,
  input: {targetUid: string; reason: string},
  requestId: string,
) {
  const {db} = deps;
  const nowMs = deps.now();
  if (input.targetUid === actor.uid) {
    throw new AdminError("cannot_modify_self");
  }
  const ref = db.doc(`${STAFF_COLLECTION}/${input.targetUid}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = parseStaffRecord(input.targetUid, snap.data());
    if (!current) {
      throw new AdminError("not_found", "staff");
    }
    assertCanManage(actor, current);
    tx.set(ref, {sessionsValidAfter: Timestamp.fromMillis(nowMs), updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "ADMIN_SESSIONS_REVOKED",
      targetType: "staff",
      targetId: input.targetUid,
      requestId,
      metadata: {role: current.role, reason: input.reason},
    }, nowMs);
  });
  await deps.auth.revokeRefreshTokens(input.targetUid);
  return {uid: input.targetUid, sessionsValidAfter: new Date(nowMs).toISOString()};
}

async function countOrNull(query: FirebaseFirestore.Query): Promise<number | null> {
  try {
    return (await query.count().get()).data().count;
  } catch {
    // A missing index must not take the page down.
    return null;
  }
}

/**
 * One colleague's record, login facts and a bounded activity summary: one
 * count() aggregation per activity group (actorAdminId + action index) and the
 * last few audit events. Never a scan of the log.
 */
export async function getStaff(deps: AdminDeps, input: {targetUid: string}) {
  const {db} = deps;
  const snap = await db.doc(`${STAFF_COLLECTION}/${input.targetUid}`).get();
  if (!snap.exists || !parseStaffRecord(input.targetUid, snap.data())) {
    throw new AdminError("not_found", "staff");
  }
  const byActor = db.collection(AUDIT_COLLECTION).where("actorAdminId", "==", input.targetUid);
  const groups = Object.entries(STAFF_ACTIVITY_GROUPS);
  const [authUser, recent, ...counts] = await Promise.all([
    deps.auth.getUser(input.targetUid).catch(() => null),
    byActor.orderBy("createdAt", "desc").limit(RECENT_ACTIVITY_LIMIT).get(),
    ...groups.map(([, actions]) => countOrNull(byActor.where("action", "in", [...actions]))),
  ]);
  const factors = authUser?.multiFactor?.enrolledFactors ?? [];
  return {
    staff: staffRow(snap),
    account: authUser
      ? {
        exists: true,
        disabled: authUser.disabled,
        emailVerified: authUser.emailVerified ?? null,
        createdAt: authUser.metadata?.creationTime ? new Date(authUser.metadata.creationTime).toISOString() : null,
        lastSignInAt: authUser.metadata?.lastSignInTime ? new Date(authUser.metadata.lastSignInTime).toISOString() : null,
        // Factor kinds only; never the enrolment secret or phone number.
        mfaFactors: factors.map((f) => f.factorId),
      }
      : {exists: false, disabled: null, emailVerified: null, createdAt: null, lastSignInAt: null, mfaFactors: []},
    activity: Object.fromEntries(groups.map(([name], i) => [name, counts[i]])),
    recentActions: recent.docs.map((doc) => ({
      eventId: doc.id,
      action: doc.get("action") ?? null,
      targetType: doc.get("targetType") ?? null,
      targetId: doc.get("targetId") ?? null,
      caseId: doc.get("caseId") ?? null,
      createdAt: iso(doc.get("createdAt")),
    })),
    lastActivityAt: recent.docs.length ? iso(recent.docs[0].get("createdAt")) : null,
  };
}
