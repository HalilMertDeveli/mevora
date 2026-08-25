#!/usr/bin/env node
/**
 * Bootstrap first admin custom claim (offline / CI operator only).
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=./serviceAccount.json \
 *     node scripts/setAdminClaim.mjs <uid> [--revoke]
 *
 * Never commit service account keys. Admin claim is not writable from clients.
 */
import {initializeApp, applicationDefault, cert} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {readFileSync} from "node:fs";

const uid = process.argv[2];
const revoke = process.argv.includes("--revoke");
if (!uid) {
  console.error("Usage: node scripts/setAdminClaim.mjs <uid> [--revoke]");
  process.exit(1);
}

const saPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (saPath) {
  const json = JSON.parse(readFileSync(saPath, "utf8"));
  initializeApp({credential: cert(json)});
} else {
  initializeApp({credential: applicationDefault()});
}

const auth = getAuth();
const user = await auth.getUser(uid);
const claims = {...(user.customClaims ?? {})};
if (revoke) {
  delete claims.admin;
} else {
  claims.admin = true;
}
await auth.setCustomUserClaims(uid, claims);
console.log(revoke ? `Revoked admin for ${uid}` : `Granted admin for ${uid}`);
console.log("User must refresh ID token (sign out/in) before admin panel works.");
