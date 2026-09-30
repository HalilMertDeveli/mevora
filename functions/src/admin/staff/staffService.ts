import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {appendAuditEvent, recordAuditEvent} from "../audit/auditService.js";
import {STAFF_COLLECTION, parseStaffRecord, type AdminActor} from "../auth/adminAuthorization.js";
import {
  ROLE_RANK,
  canGrantRole,
  canManageStaffMember,
  permissionsForRole,
  type AdminRole,
} from "../auth/roles.js";
import type {AdminDeps} from "../deps.js";
import {AdminError} from "../errors.js";
import {iso} from "../validation.js";

/**
 * Staff management: `adminStaff/{uid}` plus the `admin` / `adminRole` custom
 * claims that mirror it.
 *
 * The staff document is the authority (authorizeAdminRequest reads it on
 * every request); the claims are a coarse, cacheable hint. Disabling a staff
 * member therefore takes effect on their very next request, and their
 * refresh tokens are revoked so the session cannot be renewed either.
 *
 * Guards: nobody changes their own role or disables themselves; roles can only
 * be granted below one's own rank (super admins excepted); the last active
 * super admin can be neither demoted nor disabled.
 */

export const PERMISSIONS_VERSION = 1;

export async function getMyStaffProfile(deps: AdminDeps, actor: AdminActor) {
  return {
    uid: actor.uid,
    role: actor.role,
    displayName: actor.displayName,
    permissions: [...actor.permissions].sort(),
    mfa: actor.mfa,
    permissionsVersion: PERMISSIONS_VERSION,
    serverTime: new Date(deps.now()).toISOString(),
  };
}

export async function recordAdminLogin(deps: AdminDeps, actor: AdminActor, requestId: string) {
  await recordAuditEvent(deps.db, {
    actorAdminId: actor.uid,
    actorRole: actor.role,
    action: "ADMIN_LOGIN",
    targetType: "staff",
    targetId: actor.uid,
    requestId,
    metadata: {mfa: actor.mfa},
  }, deps.now());
  return getMyStaffProfile(deps, actor);
}

export async function listStaff(deps: AdminDeps) {
  const snap = await deps.db.collection(STAFF_COLLECTION).orderBy("createdAt", "asc").limit(200).get();
  return {
    items: snap.docs.map((doc) => {
      const record = parseStaffRecord(doc.id, doc.data());
      return {
        uid: doc.id,
        role: record?.role ?? doc.get("role") ?? null,
        status: record?.status ?? "disabled",
        displayName: record?.displayName ?? null,
        email: record?.email ?? null,
        createdAt: iso(doc.get("createdAt")),
        updatedAt: iso(doc.get("updatedAt")),
        lastRoleChangeBy: doc.get("lastRoleChangeBy") ?? null,
      };
    }),
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

/**
 * Grants a role to a Firebase Auth user (by uid or email), or changes an
 * existing staff member's role. The account must already exist in Auth; this
 * never creates a login.
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
  const authUser = await deps.auth.getUser(targetUid).catch(() => null);
  if (!authUser) {
    throw new AdminError("not_found", "auth_user");
  }
  const ref = db.doc(`${STAFF_COLLECTION}/${targetUid}`);
  const uid = targetUid;
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = parseStaffRecord(uid, snap.data());
    const superAdmins = current?.role === "super_admin" && input.role !== "super_admin"
      ? await countActiveSuperAdmins(tx, deps)
      : null;
    if (current && !canManageStaffMember(actor.role, current.role)) {
      throw new AdminError(current.role === "super_admin" ? "cannot_modify_super_admin" : "cannot_modify_staff");
    }
    if (superAdmins !== null && current?.status === "active" && superAdmins <= 1) {
      throw new AdminError("last_super_admin");
    }
    if (current && current.role === input.role && current.status === "active") {
      return {changed: false, previousRole: current.role};
    }
    tx.set(ref, {
      uid,
      role: input.role,
      status: "active",
      displayName: input.displayName ?? current?.displayName ?? null,
      email: authUser.email ?? current?.email ?? null,
      permissionsVersion: PERMISSIONS_VERSION,
      lastRoleChangeBy: actor.uid,
      // A role change re-issues the session: tokens minted under the old role
      // are refused from now on.
      sessionsValidAfter: Timestamp.fromMillis(nowMs),
      updatedAt: FieldValue.serverTimestamp(),
      ...(snap.exists ? {} : {createdAt: FieldValue.serverTimestamp(), createdBy: actor.uid}),
    }, {merge: true});
    appendAuditEvent(tx, db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: current ? "ADMIN_ROLE_CHANGED" : "ADMIN_GRANTED",
      targetType: "staff",
      targetId: uid,
      requestId,
      metadata: {previousRole: current?.role ?? null, previousStatus: current?.status ?? null, newRole: input.role},
    }, nowMs);
    return {changed: true, previousRole: current?.role ?? null};
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
    if (!canManageStaffMember(actor.role, current.role)) {
      throw new AdminError(current.role === "super_admin" ? "cannot_modify_super_admin" : "cannot_modify_staff");
    }
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
