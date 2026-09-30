#!/usr/bin/env node
/**
 * Grants the FIRST Trust & Safety staff role (normally super_admin) — the one
 * that cannot be granted from the console, because nobody holds
 * admin.manage_roles yet. Every later role change goes through the console
 * (adminUpdateStaffRole), which is audited and guarded.
 *
 * The person must already have a Firebase Auth account (email/password). The
 * script writes adminStaff/{uid}, mirrors the admin / adminRole custom claims,
 * revokes their existing sessions and appends an ADMIN_GRANTED audit event.
 *
 * Production (owner-run, with Application Default Credentials for the project):
 *   node tool/adminBootstrapStaff.cjs --project mevora-d6ed0 --email you@example.com --role super_admin --confirm
 *
 * Emulator: set FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST first;
 * --confirm is still required.
 *
 * Refuses to run without --project and --confirm, and refuses to overwrite an
 * existing active super admin record.
 */
const path = require("node:path");
const {createRequire} = require("node:module");

const args = process.argv.slice(2);
const arg = (name) => {
  const index = args.indexOf(`--${name}`);
  return index >= 0 ? args[index + 1] : undefined;
};
const project = arg("project");
const email = (arg("email") || "").trim().toLowerCase();
const role = arg("role") || "super_admin";
const confirmed = args.includes("--confirm");
const ROLES = ["support_agent", "moderator", "senior_moderator", "trust_safety_admin", "super_admin"];

if (!project || !email || !confirmed || !ROLES.includes(role)) {
  console.error("Usage: node tool/adminBootstrapStaff.cjs --project <id> --email <staff email> --role <role> --confirm");
  process.exit(1);
}

const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST);
if (emulated && !(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST)) {
  console.error("REFUSING TO RUN: set both emulator hosts, or neither.");
  process.exit(1);
}

const admin = createRequire(path.join(__dirname, "..", "functions", "package.json"))("firebase-admin");
admin.initializeApp({projectId: project});
const db = admin.firestore();
const auth = admin.auth();

async function main() {
  console.log(`${emulated ? "EMULATOR" : "PRODUCTION"} project ${project}: grant ${role} to ${email}`);
  const user = await auth.getUserByEmail(email);
  const ref = db.doc(`adminStaff/${user.uid}`);
  const existing = await ref.get();
  if (existing.exists && existing.get("status") === "active" && existing.get("role") === "super_admin") {
    console.log("Already an active super admin — nothing to do.");
    return;
  }
  const nowMs = Date.now();
  await db.runTransaction(async (tx) => {
    tx.set(ref, {
      uid: user.uid,
      role,
      status: "active",
      displayName: user.displayName || null,
      email,
      permissionsVersion: 1,
      sessionsValidAfter: admin.firestore.Timestamp.fromMillis(nowMs),
      createdBy: "bootstrap",
      lastRoleChangeBy: "bootstrap",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    tx.create(db.doc(`adminAuditLog/aud_bootstrap_${nowMs.toString(36)}_${user.uid.slice(0, 8)}`), {
      actorAdminId: "bootstrap",
      actorRole: "system",
      action: "ADMIN_GRANTED",
      targetType: "staff",
      targetId: user.uid,
      caseId: null,
      actionId: null,
      requestId: null,
      metadata: {newRole: role, via: "tool/adminBootstrapStaff.cjs"},
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  await auth.setCustomUserClaims(user.uid, {...(user.customClaims || {}), admin: true, adminRole: role});
  await auth.revokeRefreshTokens(user.uid);
  console.log(`Done. ${email} is ${role}. They sign in at the admin console and must enrol TOTP on first sign-in.`);
}

main().then(() => process.exit(0), (error) => {
  console.error(error.message || error);
  process.exit(1);
});
