import {PERMISSIONS, type Permission} from "./permissions.js";

/**
 * The single authority for role → permission mapping.
 *
 * Nothing else in the codebase may decide what a role can do: not the admin
 * web (which only hides buttons), not a custom claim, not a Firestore field a
 * client could write. `adminStaff/{uid}.role` names the role; this table says
 * what that role is allowed to do, at the moment the request is served.
 */
export const ADMIN_ROLES = [
  "support_agent",
  "moderator",
  "senior_moderator",
  "trust_safety_admin",
  "super_admin",
] as const;

export type AdminRole = (typeof ADMIN_ROLES)[number];

export function isAdminRole(value: unknown): value is AdminRole {
  return typeof value === "string" && (ADMIN_ROLES as readonly string[]).includes(value);
}

/**
 * Seniority, used only for staff-management guards: nobody may act on, or
 * grant, a role at or above their own (super_admin excepted for grants).
 */
export const ROLE_RANK: Readonly<Record<AdminRole, number>> = {
  support_agent: 1,
  moderator: 2,
  senior_moderator: 3,
  trust_safety_admin: 4,
  super_admin: 5,
};

const SUPPORT_AGENT: readonly Permission[] = [
  "dashboard.read",
  // Basic user card only; contact identifiers need user.read_sensitive.
  "user.read",
  "support.read",
  "support.reply",
  "support.assign",
  "support.resolve",
  "support.escalate",
  // A ban appeal arrives as a support ticket (banned accounts cannot sign in);
  // the agent files it, a senior moderator decides it.
  "appeal.create",
  "appeal.read",
];

const MODERATOR: readonly Permission[] = [
  "dashboard.read",
  "user.read",
  "user.warn",
  "user.suspend",
  "report.read",
  "report.assign",
  "report.resolve",
  "case.read",
  "case.assign",
  "case.resolve",
  "case.escalate",
  "case.note",
  "photo.read",
  "photo.approve",
  "photo.reject",
  "photo.escalate",
  "humor.read",
  "humor.moderate",
  "support.read",
  "support.escalate",
  "verification.read",
  "verification.escalate",
  "automation.read",
  "appeal.read",
];

const SENIOR_MODERATOR: readonly Permission[] = [
  ...MODERATOR,
  "user.ban",
  "user.restore",
  "case.reassign",
  "verification.require_reverification",
  "appeal.create",
  "appeal.assign",
  "appeal.resolve",
];

const TRUST_SAFETY_ADMIN: readonly Permission[] = [
  ...SENIOR_MODERATOR,
  ...SUPPORT_AGENT,
  "user.read_sensitive",
  "automation.review",
  "automation.resolve_sensitive",
  "audit.read",
];

const SUPER_ADMIN: readonly Permission[] = [...PERMISSIONS];

export const ROLE_PERMISSIONS: Readonly<Record<AdminRole, ReadonlySet<Permission>>> = {
  support_agent: new Set(SUPPORT_AGENT),
  moderator: new Set(MODERATOR),
  senior_moderator: new Set(SENIOR_MODERATOR),
  trust_safety_admin: new Set(TRUST_SAFETY_ADMIN),
  super_admin: new Set(SUPER_ADMIN),
};

export function permissionsForRole(role: AdminRole): ReadonlySet<Permission> {
  return ROLE_PERMISSIONS[role];
}

export function roleHasPermission(role: AdminRole, permission: Permission): boolean {
  return ROLE_PERMISSIONS[role].has(permission);
}

/**
 * Whether `actorRole` may put somebody into `targetRole`.
 *
 * A super admin may grant anything. Everyone else holding admin.manage_roles
 * may only grant roles strictly below their own, so a role can never be used
 * to mint an equal or higher one.
 */
export function canGrantRole(actorRole: AdminRole, targetRole: AdminRole): boolean {
  if (actorRole === "super_admin") {
    return true;
  }
  return ROLE_RANK[targetRole] < ROLE_RANK[actorRole];
}

/** Whether `actorRole` may change or disable a colleague currently in `targetRole`. */
export function canManageStaffMember(actorRole: AdminRole, targetRole: AdminRole): boolean {
  if (actorRole === "super_admin") {
    return true;
  }
  return ROLE_RANK[targetRole] < ROLE_RANK[actorRole];
}
