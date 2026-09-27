#!/usr/bin/env node
/**
 * Seeds the curated humor calibration catalogue into the Firebase Emulator
 * Suite, so "Mizahını Keşfet" has content to calibrate on locally.
 *
 * It writes exactly what the admin-only `seedInternalHumorContent` callable
 * writes: every INTERNAL_HUMOR_SEED item through `upsertHumorContentDoc`, as
 * approved and active. Both come from the COMPILED functions output, so the
 * emulator gets the same catalogue the deployed functions would seed.
 *
 * Emulator only. It refuses to run unless FIRESTORE_EMULATOR_HOST points at a
 * loopback address; with that variable set the Admin SDK cannot reach a cloud
 * database at all.
 *
 * Idempotent. `upsertHumorContentDoc` merges, keeps each item's createdAt and
 * stats, and never touches users/*, so re-running it (tool/ensure_emulators.ps1
 * does on every F5) refreshes the catalogue without resetting anyone's
 * calibration progress, ratings or profile.
 *
 * Usage, from the repo root (PowerShell):
 *
 *   npm --prefix functions run build
 *   $env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
 *   node tool/seedEmulatorHumorCatalog.cjs [--project mevora-d6ed0]
 *
 * The project defaults to QA_PROJECT_ID, then mevora-d6ed0 — the project the
 * app's "full emulator suite" launch configuration talks to. It must match the
 * --project the emulators were started with.
 */
const fs = require("node:fs");
const path = require("node:path");
const {createRequire} = require("node:module");

const FUNCTIONS_DIR = path.join(__dirname, "..", "functions");
const fromFunctions = createRequire(path.join(FUNCTIONS_DIR, "package.json"));

// --------------------------------------------------------------------------
// Guard rails — before anything is loaded or initialised
// --------------------------------------------------------------------------

const LOOPBACK_HOST = /^(?:127(?:\.\d{1,3}){3}|localhost|\[::1\]):\d{1,5}$/i;

const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!firestoreHost) {
  console.error(
    "REFUSING TO RUN: FIRESTORE_EMULATOR_HOST is not set. This script only " +
      "ever seeds the Firestore emulator (e.g. 127.0.0.1:8080).",
  );
  process.exit(2);
}
if (!LOOPBACK_HOST.test(firestoreHost)) {
  console.error(
    `REFUSING TO RUN: FIRESTORE_EMULATOR_HOST="${firestoreHost}" is not a ` +
      "loopback address (127.x.x.x, localhost or [::1]).",
  );
  process.exit(2);
}

const argv = process.argv.slice(2);
const projectFlag = argv.indexOf("--project");
const projectId =
  projectFlag >= 0 ? argv[projectFlag + 1] : process.env.QA_PROJECT_ID || "mevora-d6ed0";
if (!projectId || !/^[a-z0-9][a-z0-9-]{2,62}$/.test(projectId)) {
  console.error("usage: node tool/seedEmulatorHumorCatalog.cjs [--project <projectId>]");
  process.exit(2);
}

// --------------------------------------------------------------------------
// Dependencies and compiled output both live under functions/
// --------------------------------------------------------------------------

function requireFromFunctions(id) {
  try {
    return fromFunctions(id);
  } catch (_) {
    console.error(`${id} not found — run: npm --prefix functions ci`);
    process.exit(2);
  }
}

function requireCompiled(relative) {
  const full = path.join(FUNCTIONS_DIR, relative);
  if (!fs.existsSync(full)) {
    console.error(
      `compiled functions output missing (functions/${relative}) — run: ` +
        "npm --prefix functions run build",
    );
    process.exit(2);
  }
  return require(full);
}

/** A seed compiled before its source changed would seed yesterday's catalogue. */
function warnIfStale(sourceRelative, compiledRelative) {
  try {
    const source = fs.statSync(path.join(FUNCTIONS_DIR, sourceRelative)).mtimeMs;
    const compiled = fs.statSync(path.join(FUNCTIONS_DIR, compiledRelative)).mtimeMs;
    if (source > compiled) {
      console.warn(
        `WARNING: functions/${sourceRelative} is newer than its compiled output — ` +
          "run: npm --prefix functions run build",
      );
    }
  } catch (_) {
    // Source not checked out next to lib (unusual); the compiled seed still works.
  }
}

const admin = requireFromFunctions("firebase-admin");
const {INTERNAL_HUMOR_SEED, upsertHumorContentDoc, HUMOR_CONTENT_COLLECTION} =
  requireCompiled("lib/humor/contentRepository.js");
const {buildCalibrationPoolReport} = requireCompiled("lib/humor/calibrationPoolReport.js");
warnIfStale("src/humor/calibrationSeed.ts", "lib/humor/calibrationSeed.js");

// --------------------------------------------------------------------------

(async () => {
  console.log("Seeding the curated humor catalogue into the Firestore emulator");
  console.log(`  target: ${firestoreHost} (emulator) · project ${projectId}`);

  admin.initializeApp({projectId});
  const db = admin.firestore();
  const collection = db.collection(HUMOR_CONTENT_COLLECTION);

  let created = 0;
  let refreshed = 0;
  for (const item of INTERNAL_HUMOR_SEED) {
    const existed = (await collection.doc(item.contentId).get()).exists;
    // Same arguments as the admin seedInternalHumorContent callable.
    await upsertHumorContentDoc(db, {
      ...item,
      safetyStatus: "approved",
      active: true,
    });
    if (existed) {
      refreshed += 1;
    } else {
      created += 1;
    }
  }
  const total = (await collection.select().get()).size;
  console.log(
    `  written: ${INTERNAL_HUMOR_SEED.length} curated items ` +
      `(${created} new, ${refreshed} refreshed) · ${HUMOR_CONTENT_COLLECTION} holds ${total} docs`,
  );

  const report = await buildCalibrationPoolReport(db);
  console.log(
    `  anchor-slot pools (calibration v${report.calibrationVersion}, ` +
      `${report.totalEligible} eligible):`,
  );
  for (const slot of report.anchorSlots) {
    console.log(
      `    ${slot.slotId.padEnd(18)} ${String(slot.candidates).padStart(2)} candidates, ` +
        `${slot.measuring} measuring ${slot.primary}` +
        `${slot.ok ? "" : "  <-- cannot rotate"}`,
    );
  }
  console.log(`  open pool (adaptive + exploration): ${report.openPoolSize}`);
  if (report.healthy) {
    console.log("  pool: healthy — calibration can run its full 15 without degrading");
  } else {
    console.warn("  WARNING: pool is NOT healthy — calibration will degrade:");
    for (const warning of report.warnings) {
      console.warn(`    - ${warning}`);
    }
  }
  process.exit(0);
})().catch((error) => {
  console.error("HUMOR CATALOGUE SEED FAILED:", error && error.message ? error.message : error);
  process.exit(1);
});
