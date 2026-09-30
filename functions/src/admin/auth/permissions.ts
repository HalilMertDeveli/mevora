/**
 * Every permission the admin platform knows.
 *
 * A permission names one capability, never a role. Commands declare the
 * permission they need; roles.ts is the only place that decides which role
 * holds which permission. Adding a capability means adding it here, granting
 * it in roles.ts, and gating exactly one command family on it.
 */
export const PERMISSIONS = [
  // Staff console basics. Every active staff member can see the dashboard
  // widgets their other permissions allow.
  "dashboard.read",

  "user.read",
  // Contact identifiers (email, phone), provider ids, auth metadata.
  "user.read_sensitive",
  "user.warn",
  "user.suspend",
  "user.ban",
  "user.restore",

  "report.read",
  "report.assign",
  "report.resolve",

  "case.read",
  "case.assign",
  // Take over, or hand off, a case somebody else holds.
  "case.reassign",
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
  "support.reply",
  "support.assign",
  "support.resolve",
  "support.escalate",

  "verification.read",
  "verification.require_reverification",
  "verification.escalate",

  "automation.read",
  "automation.review",
  // Closing compliance-sensitive jobs (deletion / identity erasure) by hand.
  "automation.resolve_sensitive",

  "appeal.read",
  "appeal.create",
  "appeal.assign",
  "appeal.resolve",

  "audit.read",

  // App Control: the owner's switches for the mobile app (maintenance,
  // minimum versions, feature kill switches, announcement). Read lets a
  // Trust & Safety admin see what members are experiencing; write is the
  // owner's (super_admin only).
  "app_control.read",
  "app_control.write",

  "admin.manage_staff",
  "admin.manage_roles",
  // Bounded backfills (lookup index, report priority). Never data edits.
  "admin.maintenance",
] as const;

export type Permission = (typeof PERMISSIONS)[number];

const PERMISSION_SET: ReadonlySet<string> = new Set(PERMISSIONS);

export function isPermission(value: unknown): value is Permission {
  return typeof value === "string" && PERMISSION_SET.has(value);
}
