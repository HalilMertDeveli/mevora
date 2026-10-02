#!/usr/bin/env node
/**
 * Takes the date of birth off every profile written before it moved to the
 * member's private account.
 *
 * profiles/{uid} is readable by every signed-in member; users/{uid} only by
 * its owner. For each profile still holding `birthDate`, in one transaction:
 *   users/{uid}      gets birthDate (unless it already has one — that one is
 *                    kept) and ageRolloverAt, the server's roll-over marker
 *   profiles/{uid}   loses birthDate and gets the current age
 * Nothing else on either document changes, `updatedAt` included.
 *
 * Run it only after the rules and functions from the same change are
 * deployed: before that, the app builds in members' hands and the old
 * completeOnboarding still read the date from the profile. Until it has run,
 * profiles written earlier keep exposing the date. See
 * docs/PROFILE_BIRTH_DATE_PRIVACY.md.
 *
 * A profile with no users/{uid} document is listed and left as it is, unless
 * --strip-orphans is given: then its date is removed and its age refreshed,
 * and no account is created for it.
 *
 * Dry run (default) lists what would change; --confirm writes. Safe to stop
 * and re-run: a processed profile is no longer found.
 *
 * Production (owner-run, Application Default Credentials):
 *   npm --prefix functions run build
 *   node tool/moveProfileBirthDates.cjs --project mevora-d6ed0 [--limit 500] [--strip-orphans] [--confirm]
 *
 * Emulator: set FIRESTORE_EMULATOR_HOST.
 */
const path = require("node:path");

const functionsDir = path.join(__dirname, "..", "functions");
// Resolve firebase-admin from functions/node_modules.
const req = require("node:module").createRequire(path.join(functionsDir, "package.json"));
const {initializeApp} = req("firebase-admin/app");
const {getFirestore} = req("firebase-admin/firestore");
const {moveProfileBirthDates} = require(path.join(functionsDir, "lib", "profileAge.js"));

function arg(name, fallback = null) {
  const index = process.argv.indexOf(`--${name}`);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

async function main() {
  const project = arg("project");
  const limit = arg("limit");
  const confirm = process.argv.includes("--confirm");
  const stripOrphans = process.argv.includes("--strip-orphans");
  if (!project || (limit !== null && !(Number(limit) > 0))) {
    console.error("Usage: --project <id> [--limit N] [--strip-orphans] [--confirm]");
    process.exit(2);
  }
  initializeApp({projectId: project});
  const db = getFirestore();

  const target = process.env.FIRESTORE_EMULATOR_HOST
    ? `emulator ${process.env.FIRESTORE_EMULATOR_HOST}`
    : "LIVE Firestore";
  console.log(`${confirm ? "WRITING" : "dry run"} — project ${project}, ${target}`);

  const result = await moveProfileBirthDates(db, {
    confirm,
    stripOrphans,
    ...(limit === null ? {} : {limit: Number(limit)}),
  });

  console.log(JSON.stringify({...result, orphans: result.orphans.length}, null, 2));
  if (result.orphans.length > 0) {
    console.log(
      stripOrphans
        ? "Profiles with no account document (date removed, no account created):"
        : "Profiles with no account document (left untouched; --strip-orphans removes their date):",
    );
    for (const uid of result.orphans) console.log(`  ${uid}`);
  }
  if (!confirm) {
    console.log("Nothing was written. Re-run with --confirm to apply.");
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
