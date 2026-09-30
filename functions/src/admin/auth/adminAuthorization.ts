import {timingSafeEqual} from "node:crypto";
import type {Firestore} from "firebase-admin/firestore";
import {AdminError} from "../errors.js";
import {toMillis} from "../validation.js";
import type {Permission} from "./permissions.js";
import {isAdminRole, permissionsForRole, type AdminRole} from "./roles.js";

/**
 * Admin request authorization.
 *
 * Every admin command runs this chain, in this order, before its handler:
 *
 *   BFF credential  — the request came from mevora-admin-web's server, not a
 *                     browser holding a stolen staff token
 *   Firebase ID token valid          (verified by the callable runtime)
 *   token.admin === true             coarse gate, cheap to check
 *   second factor used for sign-in   MFA (production: always)
 *   adminStaff/{uid} exists
 *   status === "active"
 *   token issued after sessionsValidAfter (revocation takes effect at once)
 *   role is a known role
 *   role grants the requested permission
 *
 * The custom claim is never the authority on its own: a staff record that is
 * missing, disabled or demoted wins over whatever the token still says, and
 * the permission set comes from roles.ts, never from the token.
 */

export const STAFF_COLLECTION = "adminStaff";

/** Header the admin web's server attaches to every admin command. */
export const BFF_HEADER = "x-mevora-admin-bff";

/**
 * Used only when the Functions emulator runs without the secret configured,
 * so local QA works out of the box. FUNCTIONS_EMULATOR is never "true" in a
 * deployed function, so this value can never authorise a production request.
 */
export const EMULATOR_DEV_BFF_SECRET = "mevora-emulator-only-bff-secret";

export type StaffStatus = "active" | "disabled";

export interface StaffRecord {
  uid: string;
  role: AdminRole;
  status: StaffStatus;
  displayName: string | null;
  email: string | null;
  permissionsVersion: number;
  /** Tokens issued (auth_time) before this instant are refused. Epoch ms. */
  sessionsValidAfterMs: number | null;
  /**
   * The platform owner. Server-owned: set only by tool/adminBootstrapStaff.cjs
   * --owner, never by a console command. The owner's account cannot be
   * demoted, disabled, sanctioned or signed out through the normal staff
   * commands; changing ownership is a separate, deliberate procedure.
   */
  isOwner: boolean;
}

export interface AdminActor {
  uid: string;
  role: AdminRole;
  permissions: ReadonlySet<Permission>;
  displayName: string | null;
  mfa: boolean;
  isOwner: boolean;
}

export interface AdminAuthEnv {
  /** The shared BFF secret, or "" when unset (fails closed). */
  bffSecret: string;
  /** Emulator-only relaxation of the second-factor requirement. */
  allowMissingMfa: boolean;
}

export interface AdminRequestLike {
  auth?: {uid: string; token: Record<string, unknown>} | null;
  rawRequest?: {headers?: Record<string, unknown>} | null;
}

export function parseStaffRecord(uid: string, data: Record<string, unknown> | undefined): StaffRecord | null {
  if (!data) {
    return null;
  }
  const role = data.role;
  if (!isAdminRole(role)) {
    return null;
  }
  return {
    uid,
    role,
    status: data.status === "active" ? "active" : "disabled",
    displayName: typeof data.displayName === "string" ? data.displayName : null,
    email: typeof data.email === "string" ? data.email : null,
    permissionsVersion: typeof data.permissionsVersion === "number" ? data.permissionsVersion : 1,
    sessionsValidAfterMs: toMillis(data.sessionsValidAfter),
    isOwner: data.isOwner === true,
  };
}

function headerValue(request: AdminRequestLike, name: string): string {
  const headers = request.rawRequest?.headers ?? {};
  const value = headers[name] ?? headers[name.toLowerCase()];
  if (Array.isArray(value)) {
    return typeof value[0] === "string" ? value[0] : "";
  }
  return typeof value === "string" ? value : "";
}

export function bffCredentialValid(presented: string, expected: string): boolean {
  if (!expected || !presented) {
    return false;
  }
  const a = Buffer.from(presented, "utf8");
  const b = Buffer.from(expected, "utf8");
  if (a.length !== b.length) {
    return false;
  }
  return timingSafeEqual(a, b);
}

/** True when the ID token records a completed second factor. */
export function tokenHasSecondFactor(token: Record<string, unknown>): boolean {
  const firebase = token.firebase as {sign_in_second_factor?: unknown} | undefined;
  return typeof firebase?.sign_in_second_factor === "string" && firebase.sign_in_second_factor.length > 0;
}

/**
 * Authorises one admin request for one permission. Throws AdminError; never
 * returns a partially-authorised actor.
 */
export async function authorizeAdminRequest(
  request: AdminRequestLike,
  permission: Permission,
  deps: {db: Firestore},
  env: AdminAuthEnv,
): Promise<AdminActor> {
  // A request that did not come through the admin web's server is refused
  // before its token is even looked at. The message is deliberately the same
  // as a plain permission failure so the endpoint is not a probe.
  if (!bffCredentialValid(headerValue(request, BFF_HEADER), env.bffSecret)) {
    throw new AdminError("permission_denied");
  }

  const auth = request.auth;
  if (!auth?.uid) {
    throw new AdminError("unauthenticated");
  }
  const token = auth.token ?? {};
  if (token.admin !== true) {
    throw new AdminError("permission_denied");
  }

  const mfa = tokenHasSecondFactor(token);
  if (!mfa && !env.allowMissingMfa) {
    throw new AdminError("mfa_required");
  }

  const staffSnap = await deps.db.doc(`${STAFF_COLLECTION}/${auth.uid}`).get();
  const staff = parseStaffRecord(auth.uid, staffSnap.data());
  if (!staff || staff.status !== "active") {
    throw new AdminError("staff_inactive");
  }

  const authTimeSeconds = typeof token.auth_time === "number" ? token.auth_time : 0;
  if (staff.sessionsValidAfterMs !== null && authTimeSeconds * 1000 < staff.sessionsValidAfterMs) {
    throw new AdminError("session_revoked");
  }

  const permissions = permissionsForRole(staff.role);
  if (!permissions.has(permission)) {
    throw new AdminError("permission_denied", "permission_denied", {permission});
  }

  return {
    uid: auth.uid,
    role: staff.role,
    permissions,
    displayName: staff.displayName,
    mfa,
    isOwner: staff.isOwner,
  };
}

/** Throws unless the actor also holds `permission` (for in-handler branches). */
export function requirePermission(actor: AdminActor, permission: Permission): void {
  if (!actor.permissions.has(permission)) {
    throw new AdminError("permission_denied", "permission_denied", {permission});
  }
}
